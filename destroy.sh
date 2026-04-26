#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${AWS_REGION:=ap-northeast-2}"

if [[ -z "${TF_STATE_BUCKET:-}" ]]; then
  echo ">>> TF_STATE_BUCKET 미설정 — bootstrap state에서 읽기"
  cd "${SCRIPT_DIR}/bootstrap"
  terraform init -reconfigure >/dev/null
  TF_STATE_BUCKET=$(terraform output -raw s3_bucket_name)
  echo "    TF_STATE_BUCKET=${TF_STATE_BUCKET}"
  cd "${SCRIPT_DIR}"
fi

INFRA_TFVARS="${SCRIPT_DIR}/infra/terraform.tfvars"
K8S_TFVARS="${SCRIPT_DIR}/k8s/terraform.tfvars"

echo "!!! 전체 인프라를 삭제합니다. 계속하려면 'yes' 입력:"
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "취소됨."
  exit 0
fi

# ── 0. ArgoCD Applications · PVC 선제 정리 ───────────────────
# ArgoCD/Helm 이 만든 ingress(ALB), PVC(EBS), Service(LB) 는 Terraform state 밖.
# 미리 지워야 ALB/ENI 잔여로 VPC destroy 막히는 사태 방지.
# 순서: workload(pod 점유 해제) → ingress/lb svc → pvc(finalizer 풀림)
echo ">>> [0/2] ArgoCD Applications · workload · PVC cleanup"
APP_NAMESPACES="ticketing monitoring"
if kubectl cluster-info >/dev/null 2>&1; then
  # 1) ArgoCD Application 먼저 — 자체 finalizer 가 자식 정리
  kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found --wait=false --timeout=30s || true

  # 2) ingress / LoadBalancer Service — ALB controller 가 회수
  kubectl delete ingress --all -A --ignore-not-found --timeout=60s || true
  kubectl get svc -A --field-selector spec.type=LoadBalancer -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | while IFS=/ read -r ns name; do
        [[ -n "$ns" && -n "$name" ]] && kubectl delete svc "$name" -n "$ns" --ignore-not-found --timeout=30s || true
      done

  # 3) workload (sts/deploy/ds/job) — pod 가 PVC 점유 풀어야 PVC 삭제 가능
  for ns in $APP_NAMESPACES; do
    kubectl delete sts,deploy,ds,job --all -n "$ns" --ignore-not-found --wait=false --timeout=30s || true
  done
  # 잔여 pod 강제 종료 (graceful 안 끝나는 거 정리)
  for ns in $APP_NAMESPACES; do
    kubectl delete pod --all -n "$ns" --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  done

  # 4) PVC 삭제 — 워크로드 사라진 뒤라 finalizer 자연스레 풀림
  kubectl delete pvc --all -A --ignore-not-found --wait=false --timeout=30s || true

  # ALB 컨트롤러가 ALB/SG/TG 회수할 시간 확보
  echo "    ALB controller가 ALB/SG 회수 중... (60s)"
  sleep 60
else
  echo "kubectl 접근 불가 — 단계 스킵 (cluster 이미 사라졌을 수 있음)"
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
