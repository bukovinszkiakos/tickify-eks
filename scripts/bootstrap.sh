#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"
PLAN_FILE="${TERRAFORM_DIR}/tfplan"
AWS_REGION="eu-central-1"
GITHUB_REPO="bukovinszkiakos/tickify-eks"

step()      { printf "\n>>> %s\n" "$1"; }
ok()        { printf "[OK]    %s\n" "$1"; }
fail()      { printf "\n[ERROR] %s\n" "$1" >&2; exit 1; }
secret_ok() { printf "[OK]    GitHub secret %-38s configured\n" "$1"; }

cleanup() { rm -f "${PLAN_FILE}"; }
trap cleanup EXIT

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

ok "AWS identity detected"
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
    printf "  Database password: "
    read -rs TF_VAR_db_password
    printf "\n"
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
  read -rs _SEEDING_ADMIN_PASSWORD
  printf "\n"
  ok "Admin password ready"
else
  ok "Admin password skipped (SEEDING_ADMIN_PASSWORD already configured)"
fi

if [[ "${_SUPERADMIN_SECRET_EXISTS}" == "false" ]]; then
  printf "  Super-admin seed password: "
  read -rs _SEEDING_SUPERADMIN_PASSWORD
  printf "\n"
  ok "Super-admin password ready"
else
  ok "Super-admin password skipped (SEEDING_SUPERADMIN_PASSWORD already configured)"
fi


cd "${TERRAFORM_DIR}"

if [[ ! -f "terraform.tfvars" ]]; then
  fail "terraform/terraform.tfvars not found. Copy terraform.tfvars.example to terraform/terraform.tfvars and fill in your values."
fi

step "Running: terraform init"
terraform init

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
read -r CONFIRM

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
  _RDS_HOST="${_RDS_ENDPOINT%%:*}"
  _RDS_PORT="${_RDS_ENDPOINT##*:}"
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
printf "  Next step:\n"
printf "\n"
printf "    git push origin master\n"
printf "\n"
printf "  GitHub Actions will build, scan, and deploy\n"
printf "  the application automatically.\n"
printf "========================================================\n"
