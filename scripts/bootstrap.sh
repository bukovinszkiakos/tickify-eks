#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
PLAN_FILE="${TERRAFORM_DIR}/tfplan"

# -- Configuration --------------------------------------------------------------
# Change these if your AWS profile name or GitHub repository is different.
AWS_PROFILE="tickify-school"
AWS_REGION="eu-central-1"
GITHUB_REPO="bukovinszkiakos/tickify-eks"

# Export AWS_PROFILE so both the AWS CLI and Terraform use the correct account.
# Without this, the [default] profile pointing to a different account may be used.
export AWS_PROFILE

# -- Helper functions -----------------------------------------------------------
step()      { printf "\n>>> %s\n" "$1"; }
ok()        { printf "[OK]    %s\n" "$1"; }
warn()      { printf "[WARN]  %s\n" "$1" >&2; }
fail()      { printf "\n[ERROR] %s\n" "$1" >&2; exit 1; }
secret_ok() { printf "[OK]    GitHub secret %-38s configured\n" "$1"; }

# Returns 0 (true) if the named GitHub secret exists in GITHUB_REPO.
# Returns 1 (false) if the secret does not exist.
# Calls fail() and exits if the GitHub CLI request itself fails.
secret_exists() {
  local secret_name="$1"
  local existing_secrets
  if ! existing_secrets="$(gh secret list --repo "${GITHUB_REPO}" --json name --jq '.[].name' 2>&1)"; then
    fail "Could not list GitHub secrets for '${GITHUB_REPO}'. Error: ${existing_secrets}"
  fi
  if printf '%s\n' "${existing_secrets}" | grep -Fxq "${secret_name}"; then
    return 0
  else
    return 1
  fi
}

cleanup() { rm -f "${PLAN_FILE}"; }
trap cleanup EXIT

# -- Parse flags ----------------------------------------------------------------
_ROTATE_JWT=false
for _arg in "$@"; do
  case "${_arg}" in
    --rotate-jwt) _ROTATE_JWT=true ;;
  esac
done
unset _arg


step "Checking prerequisites"

for cmd in terraform aws helm kubectl gh openssl; do
  if ! command -v "$cmd" &>/dev/null; then
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


step "Validating GitHub CLI"

if ! gh auth status &>/dev/null; then
  fail "GitHub CLI is not authenticated. Run: gh auth login"
fi

if ! gh repo view "${GITHUB_REPO}" --json name &>/dev/null; then
  fail "GitHub CLI cannot access repository '${GITHUB_REPO}'. Check authentication and repository permissions."
fi

ok "GitHub CLI authenticated"
ok "Repository ${GITHUB_REPO} accessible"


step "Checking existing GitHub secrets"

if secret_exists "DB_CONNECTION_STRING";        then _DB_SECRET_EXISTS=true;        else _DB_SECRET_EXISTS=false;        fi
if secret_exists "SEEDING_ADMIN_PASSWORD";      then _ADMIN_SECRET_EXISTS=true;      else _ADMIN_SECRET_EXISTS=false;      fi
if secret_exists "SEEDING_SUPERADMIN_PASSWORD"; then _SUPERADMIN_SECRET_EXISTS=true; else _SUPERADMIN_SECRET_EXISTS=false; fi

ok "Secret inventory complete"


step "Collecting required passwords"

if [[ "${_ADMIN_SECRET_EXISTS}" == "false" ]]; then
  printf "  Admin seed password: "
  read -rs _SEEDING_ADMIN_PASSWORD || fail "Password input was interrupted. Aborting."
  printf "\n"
  ok "Admin password ready"
else
  ok "Admin password skipped (SEEDING_ADMIN_PASSWORD already configured)"
fi

if [[ "${_SUPERADMIN_SECRET_EXISTS}" == "false" ]]; then
  printf "  Super-admin seed password: "
  read -rs _SEEDING_SUPERADMIN_PASSWORD || fail "Password input was interrupted. Aborting."
  printf "\n"
  ok "Super-admin password ready"
else
  ok "Super-admin password skipped (SEEDING_SUPERADMIN_PASSWORD already configured)"
fi


step "Provisioning Terraform state bucket"

# Bootstrap Terraform uses a local backend. The state file is stored at
# terraform/bootstrap/terraform.tfstate and is gitignored -- do not commit it.
# It must be preserved on the machine running this script.
#
# When the local state file is present and the bucket already exists,
# terraform apply is a no-op. If the state file is lost (for example after a
# fresh clone), the four S3 resources must be imported manually before running
# apply. From inside terraform/bootstrap, run:
#
#   terraform init -reconfigure
#   terraform import -var="region=eu-central-1" \
#     aws_s3_bucket.state akos-tickify-tfstate-905030436561
#   terraform import -var="region=eu-central-1" \
#     aws_s3_bucket_versioning.state akos-tickify-tfstate-905030436561
#   terraform import -var="region=eu-central-1" \
#     aws_s3_bucket_server_side_encryption_configuration.state akos-tickify-tfstate-905030436561
#   terraform import -var="region=eu-central-1" \
#     aws_s3_bucket_public_access_block.state akos-tickify-tfstate-905030436561
cd "${TERRAFORM_DIR}/bootstrap"
terraform init -reconfigure
terraform apply -auto-approve -var="region=${AWS_REGION}"
STATE_BUCKET="$(terraform output -raw bucket_name)"
ok "State bucket ready: ${STATE_BUCKET}"


step "Running: terraform init"

cd "${TERRAFORM_DIR}"
terraform init \
  -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"


step "Checking Terraform state for existing RDS instance"

# Capture the output and exit code separately so a backend access failure
# (non-zero exit) is not silently treated as "RDS not found" (empty output).
_STATE_RDS=""
_STATE_RC=0
_STATE_RDS="$(terraform state list module.rds.aws_db_instance.this 2>&1)" \
  || _STATE_RC=$?

if [[ "${_STATE_RC}" -ne 0 ]]; then
  # Two non-error cases produce a non-zero exit from `terraform state list`:
  #   1. First deployment: no remote state object exists yet.
  #   2. Re-deployment after destroy: state file exists but the specific
  #      resource address is absent because it was previously destroyed.
  # Both are expected "no RDS exists" states and must not abort the script.
  # Any other non-zero exit (AccessDenied, bad credentials, S3 error, …)
  # is a genuine backend failure and must surface as a fatal error.
  if [[ "${_STATE_RDS}" == *"No state file was found!"* ]] || \
     [[ "${_STATE_RDS}" == *"The current state contains no resource"* ]]; then
    _STATE_RDS=""
  else
    fail "Failed to read Terraform state while checking for an existing RDS instance. Error: ${_STATE_RDS}"
  fi
fi

if [[ -n "${_STATE_RDS}" ]] && [[ "${_DB_SECRET_EXISTS}" == "true" ]]; then
  # RDS exists in Terraform state and the GitHub secret is already present.
  # The password is not needed for this run.
  ok "RDS instance confirmed in Terraform state -- database password not required"
else
  # The database password is required in this branch.  Two sub-cases reach here:
  #   - RDS exists in state but DB_CONNECTION_STRING is missing from GitHub.
  #   - No RDS in state (fresh deployment or re-deployment after a destroy).
  _DB_SECRET_EXISTS=false

  if [[ -z "${TF_VAR_db_password:-}" ]]; then
    printf "\n"
    if [[ -n "${_STATE_RDS}" ]]; then
      printf "  RDS instance found in Terraform state but DB_CONNECTION_STRING\n"
      printf "  is missing from GitHub secrets. Enter the ORIGINAL database\n"
      printf "  password -- Terraform does not update an existing RDS password\n"
      printf "  (lifecycle ignore_changes). The connection string will be created\n"
      printf "  in GitHub secrets after a successful apply.\n"
    else
      printf "  No RDS instance found in Terraform state.\n"
      printf "  A database password is required to create a new RDS instance.\n"
      printf "  If you are re-deploying after a destroy, enter the SAME original\n"
      printf "  password -- Terraform does not update an existing RDS password\n"
      printf "  (lifecycle ignore_changes). Entering a different value will NOT\n"
      printf "  change the database password but WILL store an incorrect connection\n"
      printf "  string in GitHub secrets.\n"
    fi
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
  else
    printf "  Using pre-exported TF_VAR_db_password.\n"
  fi

  if [[ -n "${_STATE_RDS}" ]]; then
    ok "Database password ready -- DB_CONNECTION_STRING will be created after apply"
  else
    ok "Database password ready for new RDS instance"
  fi
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

unset TF_VAR_developer_iam_arn


step "Reading infrastructure outputs"

_CLUSTER_NAME="$(terraform output -raw cluster_name)"
_ALB_ROLE_ARN="$(terraform output -raw alb_controller_role_arn)"
_APP_ROLE_ARN="$(terraform output -raw app_pod_role_arn)"
_GH_ROLE_ARN="$(terraform output -raw github_actions_role_arn)"
_BUCKET_NAME="$(terraform output -raw bucket_name)"
_RDS_ENDPOINT="$(terraform output -raw rds_endpoint)"
_DB_USERNAME="$(terraform output -raw db_username)"
_VPC_ID="$(terraform output -raw vpc_id)"
_ECR_BACKEND_URL="$(terraform output -raw ecr_repository_url)"
_ECR_FRONTEND_URL="$(terraform output -raw frontend_ecr_repository_url)"

ok "Infrastructure outputs collected"


step "Configuring kubeconfig"

aws eks update-kubeconfig \
  --name "${_CLUSTER_NAME}" \
  --region "${AWS_REGION}"

ok "kubeconfig configured for cluster: ${_CLUSTER_NAME}"


step "Configuring ALB Controller ServiceAccount"

# IRSA requires a Kubernetes ServiceAccount annotated with the IAM role ARN.
# The annotation tells EKS which IAM role the service account is allowed to assume.
# This ServiceAccount is created before Helm so the chart can use it immediately
# (the chart is installed with serviceAccount.create=false).
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${_ALB_ROLE_ARN}
EOF

ok "ALB Controller ServiceAccount configured"
unset _ALB_ROLE_ARN


step "Installing AWS Load Balancer Controller"

helm repo add eks https://aws.github.io/eks-charts &>/dev/null || true
helm repo update eks >/dev/null

# Chart version is pinned for reproducibility.
# To find the latest stable version:
#   helm search repo eks/aws-load-balancer-controller --versions | head -10
# Verify the chosen version supports your EKS Kubernetes version before updating.
HELM_CHART_VERSION="1.11.0"

# serviceAccount.create=false tells the chart to use the existing ServiceAccount
# that was created above with the IRSA annotation. The region flag is required
# by the controller for making AWS API calls.
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version "${HELM_CHART_VERSION}" \
  --namespace kube-system \
  --set clusterName="${_CLUSTER_NAME}" \
  --set vpcId="${_VPC_ID}" \
  --set region="${AWS_REGION}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --timeout 120s \
  --wait

step "Waiting for ALB Controller rollout"

kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=120s

ok "ALB Controller is ready"
unset _VPC_ID HELM_CHART_VERSION


step "Configuring GitHub repository secrets"

printf '%s' "${_GH_ROLE_ARN}" | gh secret set GH_ACTIONS_ROLE_ARN --repo "${GITHUB_REPO}"
secret_ok "GH_ACTIONS_ROLE_ARN"
unset _GH_ROLE_ARN

printf '%s' "${_APP_ROLE_ARN}" | gh secret set APP_POD_ROLE_ARN --repo "${GITHUB_REPO}"
secret_ok "APP_POD_ROLE_ARN"
unset _APP_ROLE_ARN

printf '%s' "${_BUCKET_NAME}" | gh secret set AWS_BUCKET_NAME --repo "${GITHUB_REPO}"
secret_ok "AWS_BUCKET_NAME"
unset _BUCKET_NAME

if [[ "${_DB_SECRET_EXISTS}" == "false" ]]; then
  [[ -z "${_RDS_ENDPOINT:-}" ]]      && fail "Cannot update DB_CONNECTION_STRING: Terraform output 'rds_endpoint' is empty. Resolve and rerun bootstrap.sh."
  [[ -z "${_DB_USERNAME:-}" ]]       && fail "Cannot update DB_CONNECTION_STRING: Terraform output 'db_username' is empty. Resolve and rerun bootstrap.sh."
  [[ -z "${TF_VAR_db_password:-}" ]] && fail "Cannot update DB_CONNECTION_STRING: database password is not set. Rerun bootstrap.sh and enter a non-empty password when prompted."
  _RDS_HOST="${_RDS_ENDPOINT%%:*}"
  _RDS_PORT="${_RDS_ENDPOINT##*:}"
  if [[ -z "${_RDS_HOST}" ]] || [[ -z "${_RDS_PORT}" ]]; then
    fail "Cannot update DB_CONNECTION_STRING: unexpected endpoint format '${_RDS_ENDPOINT}'. Expected host:port."
  fi
  # Verify the port contains only digits (no letters, spaces, or symbols).
  case "${_RDS_PORT}" in
    *[!0-9]*)
      fail "Cannot update DB_CONNECTION_STRING: port '${_RDS_PORT}' contains non-numeric characters."
      ;;
  esac
  # Reject values longer than 5 digits before attempting arithmetic.
  # A valid port is at most 65535 (5 digits).
  if [[ "${#_RDS_PORT}" -gt 5 ]]; then
    fail "Cannot update DB_CONNECTION_STRING: port '${_RDS_PORT}' is too long to be a valid port number."
  fi
  # Force base-10 conversion so a value with leading zeros (e.g. "0080") is
  # not silently interpreted as octal by Bash arithmetic.
  _RDS_PORT_NUMBER=$((10#${_RDS_PORT}))
  # Verify the port is within the valid TCP port range.
  if [[ "${_RDS_PORT_NUMBER}" -lt 1 ]] || [[ "${_RDS_PORT_NUMBER}" -gt 65535 ]]; then
    fail "Cannot update DB_CONNECTION_STRING: port '${_RDS_PORT}' is outside the valid range 1-65535."
  fi
  unset _RDS_PORT_NUMBER
  _CONN_STR="Server=${_RDS_HOST},${_RDS_PORT};Database=TickifyDb;User Id=${_DB_USERNAME};Password=${TF_VAR_db_password};TrustServerCertificate=True;"
  printf '%s' "${_CONN_STR}" | gh secret set DB_CONNECTION_STRING --repo "${GITHUB_REPO}"
  secret_ok "DB_CONNECTION_STRING"
  unset _RDS_HOST _RDS_PORT _CONN_STR
else
  ok "GitHub secret DB_CONNECTION_STRING preserved"
fi
unset _RDS_ENDPOINT _DB_USERNAME TF_VAR_db_password _DB_SECRET_EXISTS

if [[ "${_ROTATE_JWT}" == "true" ]] || ! secret_exists "JWT_SIGNING_KEY"; then
  _JWT_KEY="$(openssl rand -base64 64 | tr -d '\n')"
  printf '%s' "${_JWT_KEY}" | gh secret set JWT_SIGNING_KEY --repo "${GITHUB_REPO}"
  unset _JWT_KEY
  if [[ "${_ROTATE_JWT}" == "true" ]]; then
    ok "GitHub secret JWT_SIGNING_KEY rotated (all active sessions will be invalidated)"
  else
    secret_ok "JWT_SIGNING_KEY"
  fi
else
  ok "GitHub secret JWT_SIGNING_KEY preserved (use --rotate-jwt to rotate)"
fi
unset _ROTATE_JWT

if [[ "${_ADMIN_SECRET_EXISTS}" == "false" ]]; then
  printf '%s' "${_SEEDING_ADMIN_PASSWORD}" | gh secret set SEEDING_ADMIN_PASSWORD --repo "${GITHUB_REPO}"
  secret_ok "SEEDING_ADMIN_PASSWORD"
  unset _SEEDING_ADMIN_PASSWORD
else
  ok "GitHub secret SEEDING_ADMIN_PASSWORD preserved"
fi
unset _ADMIN_SECRET_EXISTS

if [[ "${_SUPERADMIN_SECRET_EXISTS}" == "false" ]]; then
  printf '%s' "${_SEEDING_SUPERADMIN_PASSWORD}" | gh secret set SEEDING_SUPERADMIN_PASSWORD --repo "${GITHUB_REPO}"
  secret_ok "SEEDING_SUPERADMIN_PASSWORD"
  unset _SEEDING_SUPERADMIN_PASSWORD
else
  ok "GitHub secret SEEDING_SUPERADMIN_PASSWORD preserved"
fi
unset _SUPERADMIN_SECRET_EXISTS


step "Configuring GitHub repository variables"

_ECR_BACKEND_REPO="${_ECR_BACKEND_URL##*/}"
_ECR_FRONTEND_REPO="${_ECR_FRONTEND_URL##*/}"
unset _ECR_BACKEND_URL _ECR_FRONTEND_URL

[[ -z "${AWS_REGION}" ]]         && fail "Cannot set GitHub Variables: AWS_REGION is empty."
[[ -z "${_ECR_BACKEND_REPO}" ]]  && fail "Cannot set GitHub Variables: ECR backend repository name is empty. Check Terraform output 'ecr_repository_url'."
[[ -z "${_ECR_FRONTEND_REPO}" ]] && fail "Cannot set GitHub Variables: ECR frontend repository name is empty. Check Terraform output 'frontend_ecr_repository_url'."
[[ -z "${_CLUSTER_NAME}" ]]      && fail "Cannot set GitHub Variables: cluster name is empty. Check Terraform output 'cluster_name'."

printf '%s' "${AWS_REGION}"         | gh variable set AWS_REGION              --repo "${GITHUB_REPO}"
ok "GitHub variable AWS_REGION configured"

printf '%s' "${_ECR_BACKEND_REPO}"  | gh variable set ECR_BACKEND_REPOSITORY  --repo "${GITHUB_REPO}"
ok "GitHub variable ECR_BACKEND_REPOSITORY configured"

printf '%s' "${_ECR_FRONTEND_REPO}" | gh variable set ECR_FRONTEND_REPOSITORY --repo "${GITHUB_REPO}"
ok "GitHub variable ECR_FRONTEND_REPOSITORY configured"

printf '%s' "${_CLUSTER_NAME}"      | gh variable set EKS_CLUSTER_NAME        --repo "${GITHUB_REPO}"
ok "GitHub variable EKS_CLUSTER_NAME configured"

unset _ECR_BACKEND_REPO _ECR_FRONTEND_REPO


step "Validating cluster"

kubectl get nodes
kubectl get pods --namespace kube-system

ok "Cluster validation complete"


printf "\n"
printf "========================================================\n"
printf "  Bootstrap complete.\n"
printf "\n"
printf "  Cluster: %s\n" "${_CLUSTER_NAME}"
printf "  Region:  %s\n" "${AWS_REGION}"
printf "\n"
printf "  GitHub secrets configured (7):\n"
printf "    GH_ACTIONS_ROLE_ARN\n"
printf "    APP_POD_ROLE_ARN\n"
printf "    AWS_BUCKET_NAME\n"
printf "    DB_CONNECTION_STRING\n"
printf "    JWT_SIGNING_KEY\n"
printf "    SEEDING_ADMIN_PASSWORD\n"
printf "    SEEDING_SUPERADMIN_PASSWORD\n"
printf "\n"
printf "  GitHub variables configured (4):\n"
printf "    AWS_REGION\n"
printf "    ECR_BACKEND_REPOSITORY\n"
printf "    ECR_FRONTEND_REPOSITORY\n"
printf "    EKS_CLUSTER_NAME\n"
printf "\n"
printf "  Next step:\n"
printf "\n"
printf "    git push origin master\n"
printf "\n"
printf "  GitHub Actions will build, scan, and deploy\n"
printf "  the application. Verify the run in the Actions tab.\n"
printf "========================================================\n"
