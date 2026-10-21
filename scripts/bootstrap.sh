#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
PLAN_FILE="${TERRAFORM_DIR}/tfplan"

step()      { printf "\n>>> %s\n" "$1"; }
ok()        { printf "[OK]    %s\n" "$1"; }
fail()      { printf "\n[ERROR] %s\n" "$1" >&2; exit 1; }
secret_ok() { printf "[OK]    GitHub secret %-38s configured\n" "$1"; }

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
  fail "Cannot determine AWS region. Set 'region = \"...\"' in terraform.tfvars or export TF_VAR_region before running bootstrap.sh."
AWS_REGION="${_TF_REGION_RAW}"
unset _TF_REGION_RAW
# ─────────────────────────────────────────────────────────────────────────────

# ── GitHub repository: read from terraform.tfvars ────────────────────────────
_GH_REPO_RAW=""
if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
  _GH_REPO_RAW="$(grep -E '^\s*github_repository\s*=' "${TERRAFORM_DIR}/terraform.tfvars" \
    | grep -v '^\s*#' \
    | sed 's/[^"]*"\([^"]*\)".*/\1/' \
    | head -1)"
fi
[[ -z "${_GH_REPO_RAW}" ]] && \
  fail "Cannot determine GitHub repository. Set 'github_repository = \"owner/repo\"' in terraform.tfvars."
[[ "${_GH_REPO_RAW}" =~ ^[^/]+/[^/]+$ ]] || \
  fail "GitHub repository '${_GH_REPO_RAW}' is not in the expected owner/repo format. Update github_repository in terraform.tfvars."
GITHUB_REPO="${_GH_REPO_RAW}"
unset _GH_REPO_RAW
# ─────────────────────────────────────────────────────────────────────────────

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


step "Validating AWS credentials"

if ! aws sts get-caller-identity --output text &>/dev/null; then
  fail "AWS credentials are not configured or are invalid. Run: aws configure"
fi

export TF_VAR_developer_iam_arn
TF_VAR_developer_iam_arn="$(aws sts get-caller-identity --query Arn --output text)"
_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

ok "AWS identity detected: account ${_ACCOUNT_ID}"
ok "Developer EKS access will be configured"


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

_SECRET_LIST="$(gh secret list --repo "${GITHUB_REPO}")"
_DB_SECRET_EXISTS=false
_ADMIN_SECRET_EXISTS=false
_SUPERADMIN_SECRET_EXISTS=false
if echo "${_SECRET_LIST}" | grep -q "^DB_CONNECTION_STRING";        then _DB_SECRET_EXISTS=true;        fi
if echo "${_SECRET_LIST}" | grep -q "^SEEDING_ADMIN_PASSWORD";      then _ADMIN_SECRET_EXISTS=true;      fi
if echo "${_SECRET_LIST}" | grep -q "^SEEDING_SUPERADMIN_PASSWORD"; then _SUPERADMIN_SECRET_EXISTS=true; fi
unset _SECRET_LIST

ok "Secret inventory complete"


step "Collecting required passwords"

if [[ "${_DB_SECRET_EXISTS}" == "false" ]]; then
  if [[ -z "${TF_VAR_db_password:-}" ]]; then
    printf "\n"
    printf "  NOTE: On the first run, this password is used to create the RDS\n"
    printf "  instance. On subsequent runs, you must enter the SAME original\n"
    printf "  password — Terraform does not update an existing RDS password\n"
    printf "  (lifecycle rule). Entering a different value will NOT change the\n"
    printf "  database password but WILL store an incorrect connection string.\n"
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
    printf "\n"
    printf "  Using pre-exported TF_VAR_db_password.\n"
    printf "  On a re-run, ensure this matches the original RDS password.\n"
    printf "\n"
  fi
  ok "Database password ready"
else
  ok "Database password skipped (DB_CONNECTION_STRING already configured)"
fi

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


cd "${TERRAFORM_DIR}"

if [[ ! -f "terraform.tfvars" ]]; then
  fail "terraform/terraform.tfvars not found. Copy terraform.tfvars.example to terraform/terraform.tfvars and fill in your values."
fi

step "Provisioning Terraform state bucket"

STATE_BUCKET="tickify-terraform-state-${_ACCOUNT_ID}"
ok "State bucket: ${STATE_BUCKET}"

_HEAD_RC=0
_HEAD_HTTP="$(aws s3api head-bucket \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" 2>&1)" || _HEAD_RC=$?

if [[ "${_HEAD_RC}" -eq 0 ]]; then
  ok "State bucket exists and is accessible"
  if aws s3api head-object \
       --bucket "${STATE_BUCKET}" \
       --key "terraform/tickify.tfstate" \
       --region "${AWS_REGION}" &>/dev/null; then
    ok "Existing Terraform state found — will be reused"
  else
    ok "Bucket is empty — ready for initial Terraform state"
  fi

elif printf '%s' "${_HEAD_HTTP}" | grep -qi "403\|Forbidden\|Access Denied"; then
  fail "State bucket '${STATE_BUCKET}' exists but cannot be accessed with the current AWS credentials. Check IAM permissions or confirm you are using the correct AWS account."

else
  ok "State bucket does not exist — creating"

  aws s3api create-bucket \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
    >/dev/null
  ok "Bucket created"

  aws s3api put-bucket-versioning \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --versioning-configuration Status=Enabled
  ok "Versioning enabled"

  aws s3api put-bucket-encryption \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  ok "Server-side encryption enabled"

  aws s3api put-public-access-block \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  ok "Public access blocked"

  ok "State bucket ready: ${STATE_BUCKET}"
fi
unset _HEAD_RC _HEAD_HTTP


step "Running: terraform init"
terraform init \
  -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}"

# ── Destroy+recreate guard ────────────────────────────────────────────────────
# The early password-skip above uses DB_CONNECTION_STRING existence as a proxy
# for "RDS already exists." This breaks if infrastructure is destroyed without
# also deleting that secret: Terraform would then create a new RDS instance
# with the placeholder default password. After init the state backend is
# accessible; check whether the RDS resource is tracked in the state file.
#
# Note: a non-empty result from terraform state list confirms only that the
# resource address is present in the Terraform state file. It does not
# independently prove that the live RDS instance exists or is healthy.
#
# Runs only on the skip path (_DB_SECRET_EXISTS=true, TF_VAR_db_password
# unset). Normal repeat runs exit immediately when the RDS is found in state.
if [[ "${_DB_SECRET_EXISTS}" == "true" ]] && [[ -z "${TF_VAR_db_password:-}" ]]; then
  _S3_STATE_RC=0
  _S3_STATE_COUNT="$(aws s3api list-objects-v2 \
    --bucket "${STATE_BUCKET}" \
    --prefix "terraform/tickify.tfstate" \
    --max-keys 1 \
    --no-paginate \
    --query 'Contents[0].Key' \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null)" || _S3_STATE_RC=$?

  _STATE_RC=0
  _STATE_OUT=""
  if [[ "${_S3_STATE_RC}" -ne 0 ]]; then
    _STATE_RC="${_S3_STATE_RC}"
  elif [[ "${_S3_STATE_COUNT}" == "terraform/tickify.tfstate" ]]; then
    _TF_STATE_ALL="$(terraform state list 2>/dev/null)" || _STATE_RC=$?
    if [[ "${_STATE_RC}" -eq 0 ]]; then
      _STATE_OUT="$(printf '%s\n' "${_TF_STATE_ALL}" | grep -F 'module.rds.aws_db_instance.this' || true)"
    fi
    unset _TF_STATE_ALL
  elif [[ "${_S3_STATE_COUNT}" != "None" ]]; then
    _STATE_RC=1
  fi
  unset _S3_STATE_RC _S3_STATE_COUNT

  if [[ "${_STATE_RC}" -ne 0 ]]; then
    fail "Terraform state could not be read (exit code ${_STATE_RC}). Cannot confirm whether an RDS instance already exists. Resolve the state backend issue and rerun bootstrap.sh."
  elif [[ -z "${_STATE_OUT}" ]]; then
    printf "\n"
    printf "  [WARNING] DB_CONNECTION_STRING secret exists, but the Terraform state\n"
    printf "  contains no RDS instance. The infrastructure may have been previously\n"
    printf "  destroyed. A real database password is required to create a new RDS\n"
    printf "  instance; DB_CONNECTION_STRING will be overwritten with the new\n"
    printf "  connection string after a successful deployment.\n"
    printf "\n"
    TF_VAR_db_password=""
    while true; do
      printf "  Database password for new RDS instance: "
      read -rs TF_VAR_db_password || fail "Password input was interrupted. Aborting."
      printf "\n"
      [[ -n "${TF_VAR_db_password}" ]] && break
      printf "  Password must not be empty. Please try again.\n"
    done
    export TF_VAR_db_password
    _DB_SECRET_EXISTS=false
    ok "Database password collected for new RDS instance"
  else
    ok "RDS instance confirmed in Terraform state — password not required"
  fi
  unset _STATE_RC _STATE_OUT
fi
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

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${_CLUSTER_NAME}" \
  --set vpcId="${_VPC_ID}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

step "Waiting for ALB Controller rollout"

kubectl rollout status deployment/aws-load-balancer-controller \
  --namespace kube-system \
  --timeout=120s

ok "ALB Controller is ready"
unset _VPC_ID


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
  [[ -z "${_RDS_HOST}" ]]                    && fail "Cannot update DB_CONNECTION_STRING: endpoint host is empty. Check Terraform output 'rds_endpoint'."
  [[ "${_RDS_HOST}" == "${_RDS_ENDPOINT}" ]] && fail "Cannot update DB_CONNECTION_STRING: endpoint has no host:port separator. Check Terraform output 'rds_endpoint'."
  [[ -z "${_RDS_PORT}" ]]                    && fail "Cannot update DB_CONNECTION_STRING: endpoint port is empty. Check Terraform output 'rds_endpoint'."
  [[ "${_RDS_PORT}" =~ ^[0-9]+$ ]]           || fail "Cannot update DB_CONNECTION_STRING: endpoint port contains non-decimal characters. Check Terraform output 'rds_endpoint'."
  [[ "${_RDS_PORT}" =~ ^0 ]]                 && fail "Cannot update DB_CONNECTION_STRING: endpoint port must not start with zero. Check Terraform output 'rds_endpoint'."
  [[ ${#_RDS_PORT} -gt 5 ]]                  && fail "Cannot update DB_CONNECTION_STRING: endpoint port value is too long to be a valid port number. Check Terraform output 'rds_endpoint'."
  if ! (( _RDS_PORT >= 1 && _RDS_PORT <= 65535 )); then
    fail "Cannot update DB_CONNECTION_STRING: endpoint port is outside the valid range 1-65535. Check Terraform output 'rds_endpoint'."
  fi
  _CONN_STR="Server=${_RDS_HOST},${_RDS_PORT};Database=TickifyDb;User Id=${_DB_USERNAME};Password=${TF_VAR_db_password};TrustServerCertificate=True;"
  printf '%s' "${_CONN_STR}" | gh secret set DB_CONNECTION_STRING --repo "${GITHUB_REPO}"
  secret_ok "DB_CONNECTION_STRING"
  unset _RDS_HOST _RDS_PORT _CONN_STR
else
  ok "GitHub secret DB_CONNECTION_STRING preserved"
fi
unset _RDS_ENDPOINT _DB_USERNAME TF_VAR_db_password _DB_SECRET_EXISTS

if [[ "${_ROTATE_JWT}" == "true" ]] || \
   ! gh secret list --repo "${GITHUB_REPO}" | grep -q "^JWT_SIGNING_KEY"; then
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

[[ -z "${AWS_REGION}" ]]         && fail "Cannot set GitHub Variables: AWS_REGION is empty. Set 'region = \"...\"' in terraform/terraform.tfvars or export TF_VAR_region before running bootstrap.sh."
[[ -z "${_ECR_BACKEND_REPO}" ]]  && fail "Cannot set GitHub Variables: ECR backend repository name is empty. Check Terraform output 'ecr_repository_url'."
[[ -z "${_ECR_FRONTEND_REPO}" ]] && fail "Cannot set GitHub Variables: ECR frontend repository name is empty. Check Terraform output 'frontend_ecr_repository_url'."
[[ -z "${_CLUSTER_NAME}" ]]      && fail "Cannot set GitHub Variables: cluster name is empty. Check Terraform output 'cluster_name'."

printf '%s' "${AWS_REGION}"         | gh variable set AWS_REGION             --repo "${GITHUB_REPO}"
ok "GitHub variable AWS_REGION configured"

printf '%s' "${_ECR_BACKEND_REPO}"  | gh variable set ECR_BACKEND_REPOSITORY --repo "${GITHUB_REPO}"
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
