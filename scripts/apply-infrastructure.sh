#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
PLAN_FILE="${TERRAFORM_DIR}/tfplan"

# -- Configuration --------------------------------------------------------------
# Change these if your AWS profile name is different.
AWS_PROFILE="tickify-school"
AWS_REGION="eu-central-1"

# Export AWS_PROFILE so both the AWS CLI and Terraform use the correct account.
# Without this, the [default] profile pointing to a different account may be used.
export AWS_PROFILE

# -- Helper functions -----------------------------------------------------------
step() { printf "\n>>> %s\n" "$1"; }
ok()   { printf "[OK]    %s\n" "$1"; }
warn() { printf "[WARN]  %s\n" "$1" >&2; }
fail() { printf "\n[ERROR] %s\n" "$1" >&2; exit 1; }

cleanup() { rm -f "${PLAN_FILE}"; }
trap cleanup EXIT


step "Checking prerequisites"

for cmd in terraform aws; do
  if ! command -v "${cmd}" &>/dev/null; then
    fail "'${cmd}' is not installed or not in PATH. Please install it and rerun this script."
  fi
  ok "${cmd} found"
done

if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
  fail "terraform/terraform.tfvars not found. Copy terraform.tfvars.example to terraform/terraform.tfvars and fill in your values."
fi


step "Validating AWS credentials"

# One call returns both the account ID and the caller ARN.
# read assigns each tab-separated field to a separate variable.
STS_OUTPUT="$(aws sts get-caller-identity --query '[Account, Arn]' --output text 2>/dev/null)" \
  || fail "AWS credentials are not configured or are invalid. Check your AWS_PROFILE setting."
read -r AWS_ACCOUNT_ID CALLER_ARN <<< "${STS_OUTPUT}"
unset STS_OUTPUT

if [[ "${AWS_ACCOUNT_ID}" != "905030436561" ]]; then
  fail "Wrong AWS account. Expected 905030436561 but got ${AWS_ACCOUNT_ID}. Check your AWS_PROFILE setting."
fi

TF_VAR_developer_iam_arn="${CALLER_ARN}"
export TF_VAR_developer_iam_arn
unset CALLER_ARN

ok "AWS account:   ${AWS_ACCOUNT_ID}"
ok "IAM identity: ${TF_VAR_developer_iam_arn}"


step "Verifying AWS region"

# Confirm the configured region is reachable by calling the EC2 AZ list.
# A missing or empty result means the region name is wrong or access is denied.
_REGION_CHECK=""
_REGION_RC=0
_REGION_CHECK="$(aws ec2 describe-availability-zones \
  --region "${AWS_REGION}" \
  --query 'AvailabilityZones[0].RegionName' \
  --output text 2>&1)" \
  || _REGION_RC=$?
if [[ "${_REGION_RC}" -ne 0 ]]; then
  fail "AWS region '${AWS_REGION}' is not accessible. Check your AWS_PROFILE and region settings. Error: ${_REGION_CHECK}"
fi
if [[ -z "${_REGION_CHECK}" ]] || [[ "${_REGION_CHECK}" == "None" ]]; then
  fail "AWS region '${AWS_REGION}' returned no usable result. Check your AWS_PROFILE and region settings."
fi
ok "AWS region verified: ${_REGION_CHECK}"
unset _REGION_CHECK _REGION_RC


step "Verifying Terraform state bucket"

# The state bucket name is derived from the verified account ID.
# If this bucket does not exist, scripts/bootstrap.sh has not been run yet.
STATE_BUCKET="akos-tickify-tfstate-${AWS_ACCOUNT_ID}"

_STATE_HEAD_RC=0
aws s3api head-bucket \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" &>/dev/null \
  || _STATE_HEAD_RC=$?

if [[ "${_STATE_HEAD_RC}" -ne 0 ]]; then
  fail "State bucket '${STATE_BUCKET}' is not accessible (exit ${_STATE_HEAD_RC}). Run scripts/bootstrap.sh first to provision the infrastructure and create the state bucket."
fi
unset _STATE_HEAD_RC

ok "State bucket accessible: ${STATE_BUCKET}"


cd "${TERRAFORM_DIR}"
ok "Working directory: ${TERRAFORM_DIR}"


step "Running: terraform init"

terraform init \
  -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"


# -- Database password check ---------------------------------------------------
# lifecycle { ignore_changes = [password] } in the RDS module means Terraform
# never updates the password for an existing instance. If RDS is already in
# Terraform state, the password variable is not required for this run.
#
# Capture the output and exit code separately so a backend access failure
# (non-zero exit) is not silently treated as "RDS not found" (empty output).
_STATE_RDS=""
_STATE_RC=0
_STATE_RDS="$(terraform state list module.rds.aws_db_instance.this 2>&1)" \
  || _STATE_RC=$?

if [[ "${_STATE_RC}" -ne 0 ]]; then
  fail "Failed to read Terraform state while checking for an existing RDS instance. Error: ${_STATE_RDS}"
fi

if [[ -n "${_STATE_RDS}" ]]; then
  ok "RDS instance found in Terraform state -- database password not required for this run"
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
    printf "  If you are re-deploying after a destroy, enter the original password --\n"
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
unset _STATE_RDS _STATE_RC


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

unset TF_VAR_developer_iam_arn TF_VAR_db_password


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
printf "  For initial setup: run scripts/bootstrap.sh -- it configures GitHub\n"
printf "  Secrets and Variables and installs the AWS Load Balancer Controller.\n"
printf "\n"
printf "  For re-applies: if Terraform outputs changed (e.g. role ARNs, bucket\n"
printf "  name), re-run scripts/bootstrap.sh to update the affected Secrets.\n"
printf "\n"
printf "  Then push to the master branch to trigger the CI/CD pipeline.\n"
printf "\n"
