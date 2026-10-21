#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
PLAN_FILE="${TERRAFORM_DIR}/tfplan"


step() { printf "\n>>> %s\n" "$1"; }
ok()   { printf "[OK]    %s\n" "$1"; }

fail() {
  printf "\n[ERROR] %s\n" "$1" >&2
  exit 1
}

cleanup() { rm -f "${PLAN_FILE}"; }
trap cleanup EXIT

# ── Region: read from terraform.tfvars or TF_VAR_region ──────────────────────
_TF_REGION_RAW=""
if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
  _TF_REGION_RAW="$(grep -E '^\s*region\s*=' "${TERRAFORM_DIR}/terraform.tfvars" \
    | grep -v '^\s*#' \
    | sed 's/[^"]*"\([^"]*\)".*/\1/' \
    | head -1)"
fi
if [[ -z "${_TF_REGION_RAW}" ]]; then
  _TF_REGION_RAW="${TF_VAR_region:-}"
fi
[[ -z "${_TF_REGION_RAW}" ]] && \
  fail "Cannot determine AWS region. Set 'region = \"...\"' in terraform.tfvars or export TF_VAR_region before running apply-infrastructure.sh."
AWS_REGION="${_TF_REGION_RAW}"
unset _TF_REGION_RAW
# ─────────────────────────────────────────────────────────────────────────────


step "Checking prerequisites"

if ! command -v terraform &>/dev/null; then
  fail "terraform is not installed or not in PATH.
        Install it from: https://developer.hashicorp.com/terraform/install"
fi
ok "$(terraform version | head -1)"

if ! command -v aws &>/dev/null; then
  fail "aws CLI is not installed or not in PATH.
        Install it from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
fi
ok "aws CLI found"

_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || fail "AWS credentials are not configured or are invalid. Run: aws configure"
STATE_BUCKET="tickify-terraform-state-${_ACCOUNT_ID}"
ok "AWS account: ${_ACCOUNT_ID}"
unset _ACCOUNT_ID

export TF_VAR_developer_iam_arn
TF_VAR_developer_iam_arn="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" \
  || fail "AWS credentials are not configured or are invalid. Run: aws configure"
ok "Developer EKS access will be configured"

_STATE_HEAD_RC=0
_STATE_HEAD_HTTP="$(aws s3api head-bucket \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" 2>&1)" || _STATE_HEAD_RC=$?

if [[ "${_STATE_HEAD_RC}" -eq 0 ]]; then
  ok "State bucket accessible: ${STATE_BUCKET}"
elif printf '%s' "${_STATE_HEAD_HTTP}" | grep -qi "403\|Forbidden\|Access Denied"; then
  fail "State bucket '${STATE_BUCKET}' exists but is not accessible with the current credentials. Check IAM permissions."
elif printf '%s' "${_STATE_HEAD_HTTP}" | grep -qi "404\|NoSuchBucket\|Not Found"; then
  fail "State bucket '${STATE_BUCKET}' does not exist. Run ./scripts/bootstrap.sh first to provision the infrastructure."
else
  fail "State bucket '${STATE_BUCKET}' could not be reached (exit ${_STATE_HEAD_RC}). Check network connectivity and AWS configuration."
fi
unset _STATE_HEAD_RC _STATE_HEAD_HTTP


cd "${TERRAFORM_DIR}"
ok "Working directory: ${TERRAFORM_DIR}"


step "Running: terraform init  (uses the remote S3 backend)"
terraform init \
  -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"


# ── Database password: required only when RDS is not yet in Terraform state ───
# lifecycle { ignore_changes = [password] } in the RDS module means Terraform
# never updates the password for an existing instance — any value (including
# the variable default) is safe to pass on repeat runs.
_S3_STATE_RC=0
_S3_STATE_COUNT="$(aws s3api list-objects-v2 \
  --bucket "${STATE_BUCKET}" \
  --prefix "terraform/tickify.tfstate" \
  --max-items 1 \
  --query 'length(Contents[?Key==`terraform/tickify.tfstate`])' \
  --output text \
  --region "${AWS_REGION}" 2>/dev/null)" || _S3_STATE_RC=$?

_RDS_STATE_RC=0
_RDS_STATE_OUT=""
if [[ "${_S3_STATE_RC}" -ne 0 ]]; then
  _RDS_STATE_RC="${_S3_STATE_RC}"
elif [[ "${_S3_STATE_COUNT}" == "1" ]]; then
  _RDS_STATE_OUT="$(terraform state list module.rds.aws_db_instance.this 2>/dev/null)" \
    || _RDS_STATE_RC=$?
elif [[ "${_S3_STATE_COUNT}" != "0" ]] && [[ "${_S3_STATE_COUNT}" != "None" ]]; then
  _RDS_STATE_RC=1
fi
unset _S3_STATE_RC _S3_STATE_COUNT

if [[ "${_RDS_STATE_RC}" -ne 0 ]]; then
  fail "Terraform state could not be read (exit code ${_RDS_STATE_RC}). Resolve the state backend issue and rerun apply-infrastructure.sh."
elif [[ -n "${_RDS_STATE_OUT}" ]]; then
  ok "RDS instance found in Terraform state — database password not required for this run"
else
  # RDS not found in Terraform state.
  # Note: absence from state does not prove that the instance is absent from AWS.
  # If an instance with the same identifier already exists in AWS, terraform apply
  # will fail with a duplicate-identifier error; no duplicate will be created.
  # Use terraform import to re-align state if needed.
  if [[ -z "${TF_VAR_db_password:-}" ]]; then
    printf "\n"
    printf "  No RDS instance found in Terraform state.\n"
    printf "  A database password is required to create a new RDS instance.\n"
    printf "  If you are re-deploying after a destroy, enter the original password —\n"
    printf "  Terraform does not update an existing RDS password (lifecycle ignore_changes).\n"
    printf "\n"
    TF_VAR_db_password=""
    while true; do
      printf "  Database password: "
      read -rs TF_VAR_db_password || fail "Password input was interrupted. Aborting."
      printf "\n"
      [[ -n "${TF_VAR_db_password}" ]] && break
      printf "  Password must not be empty. Please try again.\n"
    done
    export TF_VAR_db_password
  fi
  ok "Database password ready for new RDS instance"
fi
unset _RDS_STATE_RC _RDS_STATE_OUT
# ─────────────────────────────────────────────────────────────────────────────

step "Running: terraform validate"
terraform validate


step "Running: terraform plan"
terraform plan -out="${PLAN_FILE}"


printf "\n"
printf "========================================================\n"
printf "  Review the plan above before continuing.\n"
printf "\n"
printf "  Applying will create real AWS infrastructure and will\n"
printf "  incur costs. This action cannot be undone automatically.\n"
printf "\n"
printf "  Type 'yes' to apply, anything else to abort: "
read -r CONFIRM || fail "Confirmation input was interrupted. Aborting."

if [[ "${CONFIRM}" != "yes" ]]; then
  printf "\nAborted. No changes were made to your AWS account.\n\n"
  exit 0
fi


step "Running: terraform apply"
terraform apply "${PLAN_FILE}"


step "Infrastructure provisioned successfully. Key outputs for your next steps:"

printf "\n"
printf "  EKS cluster name:          %s\n" "$(terraform output -raw cluster_name)"
printf "  Backend ECR URL:           %s\n" "$(terraform output -raw ecr_repository_url)"
printf "  Frontend ECR URL:          %s\n" "$(terraform output -raw frontend_ecr_repository_url)"
printf "  S3 bucket name:            %s\n" "$(terraform output -raw bucket_name)"
printf "  GitHub Actions role ARN:   %s\n" "$(terraform output -raw github_actions_role_arn)"
printf "  App pod role ARN:          %s\n" "$(terraform output -raw app_pod_role_arn)"
printf "  ALB controller role ARN:   %s\n" "$(terraform output -raw alb_controller_role_arn)"
printf "\n"

printf "Next steps:\n"
printf "  For initial setup: run scripts/bootstrap.sh — it configures GitHub\n"
printf "  Secrets and Variables and installs the AWS Load Balancer Controller.\n"
printf "\n"
printf "  For re-applies: if Terraform outputs changed (e.g. role ARNs, bucket\n"
printf "  name), re-run scripts/bootstrap.sh to update the affected Secrets.\n"
printf "\n"
printf "  Then push to the master branch to trigger the CI/CD pipeline.\n"
printf "\n"
