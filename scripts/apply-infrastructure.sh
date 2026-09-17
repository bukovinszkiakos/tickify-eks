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

if [[ -z "${TF_VAR_db_password:-}" ]]; then 
  printf "\n[ERROR] TF_VAR_db_password is not set.\n\n" >&2
  printf "        Export it in your shell before running this script:\n\n" >&2
  printf "          export TF_VAR_db_password='your-database-password'\n\n" >&2
  printf "        This variable is never stored in any file — Terraform reads it\n" >&2
  printf "        directly from your shell environment at runtime only.\n\n" >&2
  exit 1
fi
ok "TF_VAR_db_password is set"


cd "${TERRAFORM_DIR}"
ok "Working directory: ${TERRAFORM_DIR}"


step "Running: terraform init  (uses the remote S3 backend)"
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
printf "  1. Configure the GitHub repository secrets listed in .github/workflows/deploy.yml\n"
printf "     with the values printed above (GH_ACTIONS_ROLE_ARN, APP_POD_ROLE_ARN, etc.).\n"
printf "  2. Install the AWS Load Balancer Controller via Helm using the ALB controller role ARN.\n"
printf "  3. Push to the master branch to trigger the GitHub Actions CI/CD pipeline.\n"
printf "\n"
