#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "${SCRIPT_DIR}/../terraform" && pwd)"

ALB_CLUSTER_TAG_VALUE="owned"
ALB_SG_TAG_KEY="elbv2.k8s.aws/cluster"

step()  { printf "\n>>> %s\n" "$1"; }
ok()    { printf "[OK]    %s\n" "$1"; }
warn()  { printf "[WARN]  %s\n" "$1" >&2; }
fail()  { printf "\n[ERROR] %s\n" "$1" >&2; exit 1; }

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
  fail "Cannot determine AWS region. Set 'region = \"...\"' in terraform.tfvars or export TF_VAR_region before running destroy.sh."
AWS_REGION="${_TF_REGION_RAW}"
unset _TF_REGION_RAW
# ─────────────────────────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 0: Safety checks and identifier capture"
# ──────────────────────────────────────────────────────────────────────────────

_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || fail "AWS credentials are not configured or are invalid. Run: aws configure"
STATE_BUCKET="tickify-terraform-state-${_ACCOUNT_ID}"
ok "AWS account: ${_ACCOUNT_ID}"

_ACTUAL_REGION="$(aws configure get region 2>/dev/null || echo "")"
if [[ -z "${_ACTUAL_REGION}" ]]; then
  _ACTUAL_REGION="${AWS_DEFAULT_REGION:-}"
fi
if [[ "${_ACTUAL_REGION}" != "${AWS_REGION}" ]]; then
  fail "Region mismatch. Configured AWS region is '${_ACTUAL_REGION}' but terraform.tfvars specifies '${AWS_REGION}'. Aborting to protect unrelated regions."
fi
ok "AWS region verified: ${_ACTUAL_REGION}"
unset _ACTUAL_REGION

ok "State bucket: ${STATE_BUCKET}"
_STATE_HEAD_RC=0
_STATE_HEAD_HTTP="$(aws s3api head-bucket \
  --bucket "${STATE_BUCKET}" \
  --region "${AWS_REGION}" 2>&1)" || _STATE_HEAD_RC=$?

if [[ "${_STATE_HEAD_RC}" -eq 0 ]]; then
  ok "State bucket accessible"
elif printf '%s' "${_STATE_HEAD_HTTP}" | grep -qi "403\|Forbidden\|Access Denied"; then
  fail "State bucket '${STATE_BUCKET}' exists but cannot be accessed. Check AWS credentials and IAM permissions."
else
  fail "State bucket '${STATE_BUCKET}' does not exist. Run ./scripts/bootstrap.sh first to provision the infrastructure."
fi
unset _STATE_HEAD_RC _STATE_HEAD_HTTP

cd "${TERRAFORM_DIR}"

step "Capturing infrastructure identifiers from Terraform state"

terraform init -reconfigure \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}" \
  >/dev/null

# ── Infrastructure identifiers ───────────────────────────────────────────────
# All four identifiers must be known before Phase 1 (confirmation gate) and
# before any destructive AWS command executes. When a Terraform output is absent
# (e.g. partial state loss), each identifier falls back to the deterministic
# formula used by its Terraform module.

_TF_CLUSTER_RAW="$(terraform output -raw cluster_name 2>/dev/null)" || true
if [[ "${_TF_CLUSTER_RAW}" =~ ^[a-z][a-z0-9-]+$ ]]; then
  CLUSTER_NAME="${_TF_CLUSTER_RAW}"
  ok "Cluster name: ${CLUSTER_NAME}"
else
  # Output missing — infrastructure may be partially destroyed or state cleared.
  # Derive from the same formula the EKS module uses: "${var.name}-eks".
  _TF_NAME_RAW=""
  if [[ -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    _TF_NAME_RAW="$(grep -E '^\s*name\s*=' "${TERRAFORM_DIR}/terraform.tfvars" \
      | grep -v '^\s*#' \
      | sed 's/[^"]*"\([^"]*\)".*/\1/' \
      | head -1)"
  fi
  CLUSTER_NAME="${_TF_NAME_RAW:-akos-tickify}-eks"
  unset _TF_NAME_RAW
  if [[ ! "${CLUSTER_NAME}" =~ ^[a-z][a-z0-9-]+$ ]]; then
    fail "Cannot determine cluster name: neither Terraform state nor terraform.tfvars provides a valid 'name'. Set 'name = ...' in terraform.tfvars and retry."
  fi
  warn "cluster_name not in Terraform state — using derived value: ${CLUSTER_NAME}"
fi
unset _TF_CLUSTER_RAW

_TF_RDS_EP="$(terraform output -raw rds_endpoint 2>/dev/null)" || true
_TF_RDS_HOST="${_TF_RDS_EP%%:*}"
RDS_IDENTIFIER="${_TF_RDS_HOST%%.*}"
if [[ "${RDS_IDENTIFIER}" =~ ^[a-z][a-z0-9-]+$ ]]; then
  ok "RDS identifier: ${RDS_IDENTIFIER}"
else
  # modules/rds/main.tf: identifier = "${var.name}-db"
  RDS_IDENTIFIER="${CLUSTER_NAME%-eks}-db"
  warn "rds_endpoint not in Terraform state — using derived identifier: ${RDS_IDENTIFIER}"
fi
unset _TF_RDS_EP _TF_RDS_HOST

_TF_ECR_BE_URL="$(terraform output -raw ecr_repository_url 2>/dev/null)" || true
ECR_BACKEND_REPO="${_TF_ECR_BE_URL##*/}"
if [[ "${ECR_BACKEND_REPO}" =~ ^[a-z][a-z0-9/_.-]+$ ]]; then
  ok "Backend ECR repository: ${ECR_BACKEND_REPO}"
else
  # modules/ecr/main.tf: name = "${var.name}-backend"
  ECR_BACKEND_REPO="${CLUSTER_NAME%-eks}-backend"
  warn "ecr_repository_url not in Terraform state — using derived name: ${ECR_BACKEND_REPO}"
fi
unset _TF_ECR_BE_URL

_TF_ECR_FE_URL="$(terraform output -raw frontend_ecr_repository_url 2>/dev/null)" || true
ECR_FRONTEND_REPO="${_TF_ECR_FE_URL##*/}"
if [[ "${ECR_FRONTEND_REPO}" =~ ^[a-z][a-z0-9/_.-]+$ ]]; then
  ok "Frontend ECR repository: ${ECR_FRONTEND_REPO}"
else
  # modules/ecr/main.tf: name = "${var.name}-frontend"
  ECR_FRONTEND_REPO="${CLUSTER_NAME%-eks}-frontend"
  warn "frontend_ecr_repository_url not in Terraform state — using derived name: ${ECR_FRONTEND_REPO}"
fi
unset _TF_ECR_FE_URL

ALB_CLUSTER_TAG_KEY="kubernetes.io/cluster/${CLUSTER_NAME}"
# ─────────────────────────────────────────────────────────────────────────────

# ── VPC ID ────────────────────────────────────────────────────────────────────
# Validate the terraform output before trusting it: Terraform warning text
# (e.g. "No outputs found") must never become a VPC filter value.
_TF_VPC_RAW="$(terraform output -raw vpc_id 2>/dev/null)" || true
if [[ "${_TF_VPC_RAW}" =~ ^vpc-[0-9a-f]+$ ]]; then
  _VPC_ID="${_TF_VPC_RAW}"
  ok "VPC ID captured from Terraform state: ${_VPC_ID}"
else
  ok "VPC ID not in Terraform state — querying AWS by name tag"
  _VPC_ID="$(aws ec2 describe-vpcs \
    --region "${AWS_REGION}" \
    --filters "Name=tag:Name,Values=${CLUSTER_NAME%-eks}-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)" || true
  if [[ "${_VPC_ID}" == "None" ]] || [[ -z "${_VPC_ID}" ]]; then
    _VPC_ID=""
    warn "Tickify VPC not found in AWS — VPC-scoped cleanup (ALB, security groups) will be skipped"
  else
    ok "VPC ID discovered via AWS: ${_VPC_ID}"
  fi
fi
unset _TF_VPC_RAW

# ── Uploads bucket ────────────────────────────────────────────────────────────
# S3 bucket names are lowercase alphanumeric + hyphens only; any other output
# (Terraform warning text contains spaces/newlines) is rejected as invalid.
_TF_BUCKET_RAW="$(terraform output -raw bucket_name 2>/dev/null)" || true
if [[ "${_TF_BUCKET_RAW}" =~ ^[a-z0-9][a-z0-9-]+[a-z0-9]$ ]] && \
   [[ "${_TF_BUCKET_RAW}" != "${STATE_BUCKET}" ]]; then
  _BUCKET_NAME="${_TF_BUCKET_RAW}"
  ok "Uploads bucket captured from Terraform state: ${_BUCKET_NAME}"
else
  ok "Uploads bucket not in Terraform state — searching by Project=tickify tag"
  _BUCKET_NAME=""
  _CANDIDATES=""
  while IFS= read -r _B; do
    [[ -z "${_B}" ]] && continue
    [[ "${_B}" == "${STATE_BUCKET}" ]] && continue
    _TAG_VAL="$(aws s3api get-bucket-tagging \
      --bucket "${_B}" \
      --region "${AWS_REGION}" \
      --query 'TagSet[?Key==`Project`].Value' \
      --output text 2>/dev/null)" || true
    if [[ "${_TAG_VAL}" == "tickify" ]]; then
      _CANDIDATES="${_CANDIDATES}${_B}"$'\n'
    fi
  done < <(aws s3api list-buckets \
    --query 'Buckets[].Name' \
    --output text 2>/dev/null | tr '\t' '\n')

  _CANDIDATE_COUNT="$(printf '%s' "${_CANDIDATES}" | grep -c '[^[:space:]]' || true)"

  if [[ "${_CANDIDATE_COUNT}" -eq 0 ]]; then
    _BUCKET_NAME=""
    ok "Uploads bucket not found in AWS — already deleted or never created"
  elif [[ "${_CANDIDATE_COUNT}" -eq 1 ]]; then
    _BUCKET_NAME="$(printf '%s' "${_CANDIDATES}" | tr -d '[:space:]')"
    ok "Uploads bucket discovered: ${_BUCKET_NAME}"
  else
    fail "Multiple S3 buckets tagged Project=tickify found (excluding state bucket). Cannot safely determine which to empty. Candidates: $(printf '%s' "${_CANDIDATES}" | tr '\n' ' ')Aborting."
  fi
  unset _CANDIDATES _CANDIDATE_COUNT _B _TAG_VAL
fi
unset _TF_BUCKET_RAW

if [[ "${_BUCKET_NAME}" == "${STATE_BUCKET}" ]]; then
  fail "CRITICAL: bucket name resolves to the Terraform state bucket '${STATE_BUCKET}'. Aborting."
fi

ok "State bucket '${STATE_BUCKET}' will not be touched"


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 1: Confirmation gate"
# ──────────────────────────────────────────────────────────────────────────────

printf "\n"
printf "  ┌─────────────────────────────────────────────────────────────────┐\n"
printf "  │  DESTRUCTIVE OPERATION                                          │\n"
printf "  │                                                                 │\n"
printf "  │  This will permanently destroy ALL Tickify infrastructure:     │\n"
printf "  │    • EKS cluster (%s)                        │\n" "${CLUSTER_NAME}"
printf "  │    • RDS SQL Server instance (%s)               │\n" "${RDS_IDENTIFIER}"
printf "  │    • ECR repositories (backend + frontend)                      │\n"
printf "  │    • VPC, subnets, NAT gateway, all networking                  │\n"
printf "  │    • S3 uploads bucket (ALL FILES DELETED)                      │\n"
printf "  │    • IAM roles, OIDC provider, ALB Controller                   │\n"
printf "  │                                                                 │\n"
printf "  │  Terraform state bucket '%s' will NOT be deleted. │\n" "${STATE_BUCKET}"
printf "  │                                                                 │\n"
printf "  │  This action cannot be undone.                                  │\n"
printf "  └─────────────────────────────────────────────────────────────────┘\n"
printf "\n"
printf "  Type the cluster name '%s' to confirm: " "${CLUSTER_NAME}"
read -r _CONFIRM || fail "Confirmation input was interrupted. Aborting."

if [[ "${_CONFIRM}" != "${CLUSTER_NAME}" ]]; then
  printf "\nAborted. No changes were made.\n\n"
  exit 0
fi
unset _CONFIRM

ok "Confirmed"


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 2: Configuring kubeconfig"
# ──────────────────────────────────────────────────────────────────────────────

if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
   --query 'cluster.status' --output text 2>/dev/null | grep -q "ACTIVE"; then
  aws eks update-kubeconfig \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}"
  ok "kubeconfig configured for ${CLUSTER_NAME}"
  _CLUSTER_REACHABLE=true
else
  warn "EKS cluster '${CLUSTER_NAME}' is not reachable or does not exist. Skipping kubectl phases."
  _CLUSTER_REACHABLE=false
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 3: Deleting Kubernetes Ingress (starts ALB removal)"
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${_CLUSTER_REACHABLE}" == "true" ]]; then
  if kubectl get ingress tickify-ingress --namespace default &>/dev/null; then
    kubectl delete ingress tickify-ingress --namespace default
    ok "Ingress 'tickify-ingress' deleted — ALB Controller will begin deprovisioning the ALB"
  else
    ok "Ingress 'tickify-ingress' not found — already deleted or never created"
  fi
else
  warn "Skipping ingress deletion (cluster not reachable)"
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 4: Waiting for ALB deletion"
# ──────────────────────────────────────────────────────────────────────────────

_alb_find_by_vpc_and_tag() {
  aws elbv2 describe-load-balancers \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[?VpcId=='${_VPC_ID}'].LoadBalancerArn" \
    --output text \
  | tr '\t' '\n' \
  | while read -r _arn; do
      if [[ -z "${_arn}" ]]; then continue; fi
      _tag_val="$(aws elbv2 describe-tags \
        --resource-arns "${_arn}" \
        --region "${AWS_REGION}" \
        --query "TagDescriptions[0].Tags[?Key=='${ALB_CLUSTER_TAG_KEY}'].Value" \
        --output text 2>/dev/null)"
      if [[ "${_tag_val}" == "${ALB_CLUSTER_TAG_VALUE}" ]]; then
        printf '%s\n' "${_arn}"
      fi
    done
}

if [[ -z "${_VPC_ID}" ]]; then
  ok "VPC not found — ALB cleanup skipped"
else
  _WAIT_SECONDS=0
  _MAX_WAIT=120
  printf "  Waiting up to %ds for ALB Controller to delete the ALB" "${_MAX_WAIT}"
  while true; do
    _ALB_ARNS="$(_alb_find_by_vpc_and_tag)"
    if [[ -z "${_ALB_ARNS}" ]]; then
      printf "\n"
      ok "No Tickify-owned ALBs found in VPC ${_VPC_ID} — clean"
      break
    fi
    if [[ "${_WAIT_SECONDS}" -ge "${_MAX_WAIT}" ]]; then
      printf "\n"
      warn "ALB still present after ${_MAX_WAIT}s. Attempting force-delete."

      while IFS= read -r _ALB_ARN; do
        if [[ -z "${_ALB_ARN}" ]]; then continue; fi

        # Verify VPC — belt-and-suspenders (already filtered above, but re-check before delete)
        _ALB_VPC="$(aws elbv2 describe-load-balancers \
          --load-balancer-arns "${_ALB_ARN}" \
          --region "${AWS_REGION}" \
          --query 'LoadBalancers[0].VpcId' \
          --output text 2>/dev/null)"

        # Verify cluster ownership tag
        _ALB_TAG="$(aws elbv2 describe-tags \
          --resource-arns "${_ALB_ARN}" \
          --region "${AWS_REGION}" \
          --query "TagDescriptions[0].Tags[?Key=='${ALB_CLUSTER_TAG_KEY}'].Value" \
          --output text 2>/dev/null)"

        if [[ "${_ALB_VPC}" != "${_VPC_ID}" ]]; then
          fail "SAFETY ABORT: ALB ${_ALB_ARN} VPC '${_ALB_VPC}' does not match Tickify VPC '${_VPC_ID}'. Refusing to delete."
        fi
        if [[ "${_ALB_TAG}" != "${ALB_CLUSTER_TAG_VALUE}" ]]; then
          fail "SAFETY ABORT: ALB ${_ALB_ARN} missing required tag '${ALB_CLUSTER_TAG_KEY}=${ALB_CLUSTER_TAG_VALUE}'. Refusing to delete."
        fi

        aws elbv2 delete-load-balancer \
          --load-balancer-arn "${_ALB_ARN}" \
          --region "${AWS_REGION}"
        ok "Force-deleted ALB: ${_ALB_ARN}"
      done <<< "${_ALB_ARNS}"

      # Wait for deletion to propagate
      _POLL=0
      while [[ -n "$(_alb_find_by_vpc_and_tag)" ]] && [[ "${_POLL}" -lt 60 ]]; do
        sleep 5
        _POLL=$(( _POLL + 5 ))
      done
      break
    fi
    printf "."
    sleep 10
    _WAIT_SECONDS=$(( _WAIT_SECONDS + 10 ))
  done
  unset _WAIT_SECONDS _MAX_WAIT _ALB_ARNS _ALB_ARN _ALB_VPC _ALB_TAG _POLL
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 5: Deleting out-of-band security groups"
# ──────────────────────────────────────────────────────────────────────────────

if [[ -z "${_VPC_ID}" ]]; then
  ok "VPC not found — security group cleanup skipped"
else
  # ── ALB Controller security groups (tagged elbv2.k8s.aws/cluster) ────────────
  _SG_IDS="$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters \
      "Name=vpc-id,Values=${_VPC_ID}" \
      "Name=tag-key,Values=${ALB_SG_TAG_KEY}" \
    --query 'SecurityGroups[*].GroupId' \
    --output text \
    | tr '\t' '\n')"

  if [[ -z "${_SG_IDS}" ]]; then
    ok "No ALB Controller security groups found in VPC ${_VPC_ID}"
  else
    while IFS= read -r _SG_ID; do
      if [[ -z "${_SG_ID}" ]]; then continue; fi
      aws ec2 delete-security-group \
        --group-id "${_SG_ID}" \
        --region "${AWS_REGION}" \
        && ok "Deleted ALB Controller security group: ${_SG_ID}" \
        || warn "Could not delete security group ${_SG_ID} — may already be deleted or still in use"
    done <<< "${_SG_IDS}"
  fi
  unset _SG_IDS _SG_ID

  # ── EKS-managed cluster security group (eks-cluster-sg-{cluster}-{random}) ───
  # EKS creates this SG automatically when the cluster is provisioned; it is NOT
  # tracked in Terraform state. EKS normally deletes it when the cluster is
  # destroyed, but if the cluster was deleted outside Terraform the SG may remain
  # as an orphan. A lingering cluster SG causes a VPC DependencyViolation that
  # prevents terraform destroy from completing.
  _EKS_SG_IDS="$(aws ec2 describe-security-groups \
    --region "${AWS_REGION}" \
    --filters \
      "Name=vpc-id,Values=${_VPC_ID}" \
      "Name=group-name,Values=eks-cluster-sg-${CLUSTER_NAME}-*" \
    --query 'SecurityGroups[*].GroupId' \
    --output text \
    | tr '\t' '\n')"

  if [[ -z "${_EKS_SG_IDS}" ]]; then
    ok "No EKS cluster security group found in VPC ${_VPC_ID} — already cleaned up"
  else
    while IFS= read -r _SG_ID; do
      if [[ -z "${_SG_ID}" ]]; then continue; fi
      aws ec2 delete-security-group \
        --group-id "${_SG_ID}" \
        --region "${AWS_REGION}" \
        && ok "Deleted EKS cluster security group: ${_SG_ID}" \
        || warn "Could not delete EKS cluster security group ${_SG_ID} — it may still have dependencies. terraform destroy may fail on VPC deletion if this is not resolved."
    done <<< "${_EKS_SG_IDS}"
  fi
  unset _EKS_SG_IDS _SG_ID
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 6: Deleting application Kubernetes resources"
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${_CLUSTER_REACHABLE}" == "true" ]]; then
  for _res in deployment/tickify-backend deployment/tickify-frontend service/tickify-service service/tickify-frontend-service; do
    if kubectl get "${_res}" --namespace default &>/dev/null; then
      kubectl delete "${_res}" --namespace default
      ok "Deleted ${_res}"
    fi
  done
  unset _res
else
  warn "Skipping Kubernetes resource deletion (cluster not reachable)"
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 7: Uninstalling AWS Load Balancer Controller Helm release"
# ──────────────────────────────────────────────────────────────────────────────

if [[ "${_CLUSTER_REACHABLE}" == "true" ]]; then
  if helm status aws-load-balancer-controller --namespace kube-system &>/dev/null; then
    helm uninstall aws-load-balancer-controller --namespace kube-system
    ok "Helm release 'aws-load-balancer-controller' uninstalled"
  else
    ok "Helm release 'aws-load-balancer-controller' not found — already removed"
  fi

  if kubectl get serviceaccount aws-load-balancer-controller --namespace kube-system &>/dev/null; then
    kubectl delete serviceaccount aws-load-balancer-controller --namespace kube-system
    ok "ServiceAccount 'aws-load-balancer-controller' deleted"
  fi
else
  warn "Skipping Helm uninstall (cluster not reachable)"
fi


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 8: Emptying S3 uploads bucket (versions and delete markers)"
# ──────────────────────────────────────────────────────────────────────────────

if [[ -z "${_BUCKET_NAME}" ]]; then
  ok "Uploads bucket was not found — S3 empty phase skipped"
elif aws s3api head-bucket --bucket "${_BUCKET_NAME}" --region "${AWS_REGION}" 2>/dev/null; then
  ok "Bucket '${_BUCKET_NAME}' found — emptying all versions and delete markers"

  # Delete all object versions
  _VERSIONS="$(aws s3api list-object-versions \
    --bucket "${_BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --query 'Versions[*].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null)"

  if [[ "${_VERSIONS}" != "null" ]] && [[ "${_VERSIONS}" != "[]" ]] && [[ -n "${_VERSIONS}" ]]; then
    aws s3api delete-objects \
      --bucket "${_BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --delete "{\"Objects\":$(printf '%s' "${_VERSIONS}"),\"Quiet\":true}" \
      >/dev/null
    ok "Object versions deleted"
  else
    ok "No object versions found"
  fi

  # Delete all delete markers
  _MARKERS="$(aws s3api list-object-versions \
    --bucket "${_BUCKET_NAME}" \
    --region "${AWS_REGION}" \
    --query 'DeleteMarkers[*].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null)"

  if [[ "${_MARKERS}" != "null" ]] && [[ "${_MARKERS}" != "[]" ]] && [[ -n "${_MARKERS}" ]]; then
    aws s3api delete-objects \
      --bucket "${_BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --delete "{\"Objects\":$(printf '%s' "${_MARKERS}"),\"Quiet\":true}" \
      >/dev/null
    ok "Delete markers removed"
  else
    ok "No delete markers found"
  fi

  unset _VERSIONS _MARKERS
  ok "Bucket '${_BUCKET_NAME}' emptied — ready for Terraform deletion"
else
  ok "Bucket '${_BUCKET_NAME}' not found — already deleted or never created"
fi
unset _BUCKET_NAME _VPC_ID


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 9: Emptying Tickify ECR repositories"
# ──────────────────────────────────────────────────────────────────────────────

for _ECR_REPO in "${ECR_BACKEND_REPO}" "${ECR_FRONTEND_REPO}"; do
  if ! aws ecr describe-repositories \
       --repository-names "${_ECR_REPO}" \
       --region "${AWS_REGION}" &>/dev/null; then
    ok "ECR repository '${_ECR_REPO}' — not found, skipping"
    continue
  fi

  while true; do
    _IMAGE_IDS="$(aws ecr list-images \
      --repository-name "${_ECR_REPO}" \
      --region "${AWS_REGION}" \
      --max-items 100 \
      --query 'imageIds' \
      --output json)"

    if [[ "${_IMAGE_IDS}" == "[]" ]] || [[ "${_IMAGE_IDS}" == "null" ]] || [[ -z "${_IMAGE_IDS}" ]]; then
      break
    fi

    aws ecr batch-delete-image \
      --repository-name "${_ECR_REPO}" \
      --region "${AWS_REGION}" \
      --image-ids "${_IMAGE_IDS}" \
      >/dev/null
  done

  _REMAINING="$(aws ecr list-images \
    --repository-name "${_ECR_REPO}" \
    --region "${AWS_REGION}" \
    --query 'length(imageIds)' \
    --output text)"

  if [[ "${_REMAINING}" != "0" ]]; then
    fail "ECR repository '${_ECR_REPO}' still has ${_REMAINING} image(s) after cleanup. Aborting."
  fi

  ok "ECR repository '${_ECR_REPO}' — all images deleted"
done
unset _ECR_REPO _IMAGE_IDS _REMAINING


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 10: terraform destroy"
# ──────────────────────────────────────────────────────────────────────────────

cd "${TERRAFORM_DIR}"

export TF_VAR_db_password="IGNORED_BY_LIFECYCLE"

terraform destroy -auto-approve

unset TF_VAR_db_password

ok "Terraform destroy complete"


# ──────────────────────────────────────────────────────────────────────────────
step "Phase 11: Final verification"
# ──────────────────────────────────────────────────────────────────────────────

_RESIDUAL=false

if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
   --query 'cluster.status' --output text 2>/dev/null | grep -qv "^$"; then
  warn "EKS cluster '${CLUSTER_NAME}' still present — manual cleanup may be required"
  _RESIDUAL=true
else
  ok "EKS cluster '${CLUSTER_NAME}' — gone"
fi

if aws rds describe-db-instances --db-instance-identifier "${RDS_IDENTIFIER}" \
   --region "${AWS_REGION}" &>/dev/null; then
  warn "RDS instance '${RDS_IDENTIFIER}' still present — manual cleanup may be required"
  _RESIDUAL=true
else
  ok "RDS instance '${RDS_IDENTIFIER}' — gone"
fi

for _ECR_REPO in "${ECR_BACKEND_REPO}" "${ECR_FRONTEND_REPO}"; do
  if aws ecr describe-repositories --repository-names "${_ECR_REPO}" \
     --region "${AWS_REGION}" &>/dev/null; then
    warn "ECR repository '${_ECR_REPO}' still present — manual cleanup may be required"
    _RESIDUAL=true
  else
    ok "ECR repository '${_ECR_REPO}' — gone"
  fi
done
unset _ECR_REPO

# Verify state bucket was not touched
if aws s3api head-bucket --bucket "${STATE_BUCKET}" --region "${AWS_REGION}" 2>/dev/null; then
  ok "Terraform state bucket '${STATE_BUCKET}' — preserved (correct)"
else
  warn "Terraform state bucket '${STATE_BUCKET}' is not accessible — investigate immediately"
fi

printf "\n"
if [[ "${_RESIDUAL}" == "true" ]]; then
  printf "========================================================\n"
  printf "  Destroy complete with warnings.\n"
  printf "  One or more resources may require manual cleanup.\n"
  printf "  See [WARN] lines above.\n"
  printf "========================================================\n"
else
  printf "========================================================\n"
  printf "  Destroy complete. All Tickify infrastructure removed.\n"
  printf "  Terraform state bucket '%s' preserved.\n" "${STATE_BUCKET}"
  printf "========================================================\n"
fi
unset _RESIDUAL _CLUSTER_REACHABLE
