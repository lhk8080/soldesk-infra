#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${TF_STATE_BUCKET:?'TF_STATE_BUCKET env var required'}"
: "${AWS_REGION:=ap-northeast-2}"

INFRA_TFVARS="${SCRIPT_DIR}/infra/terraform.tfvars"
K8S_TFVARS="${SCRIPT_DIR}/k8s/terraform.tfvars"

echo "!!! 전체 인프라를 삭제합니다. 계속하려면 'yes' 입력:"
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "취소됨."
  exit 0
fi

# ── 1. k8s addons 먼저 제거 ──────────────────────────────────
echo ">>> [1/2] k8s addons destroy"
cd "${SCRIPT_DIR}/k8s"
terraform init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="key=k8s/terraform.tfstate"
terraform destroy -var-file="${K8S_TFVARS}" -auto-approve || true

# ── 2. infra 제거 ────────────────────────────────────────────
# compute module의 destroy provisioner가 ALB/ENI/SG 정리 후 VPC 삭제
echo ">>> [2/2] infra destroy"
cd "${SCRIPT_DIR}/infra"
terraform init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="key=infra/terraform.tfstate"
terraform destroy -var-file="${INFRA_TFVARS}" -auto-approve

echo ""
echo "=== Destroy 완료 ==="
