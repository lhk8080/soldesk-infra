#!/usr/bin/env bash
# Terraform apply 래퍼 (4단계):
#   1. EKS cold-start
#   2. ArgoCD(helm) + ALB controller 먼저 apply
#   3. ArgoCD Application CR 생성 (계정 고유 값을 Helm parameters 로 런타임 주입)
#        → repo 에는 계정 ID/ECR URL 이 없어서 팀원들이 shared repo 를 그대로 사용 가능
#        → 이미지 태그는 기존 Application 의 값을 보존(있으면). 없으면 "seed-pending".
#        → 실제 SHA 로 교체는 soldesk-app/scripts/seed.sh 가 kubectl patch 로 수행.
#   4. 전체 terraform apply (api_gateway.wait_for_alb 통과)
set -euo pipefail
cd "$(dirname "$0")"

REGION="${AWS_REGION:-ap-northeast-2}"
K8S_REPO_URL="${K8S_REPO_URL:-https://github.com/lhk8080/soldesk-k8s.git}"
K8S_REPO_REVISION="${K8S_REPO_REVISION:-main}"

if [ -z "${TF_VAR_db_password:-}" ] && ! grep -q '^db_password' terraform.tfvars 2>/dev/null; then
  echo "ERROR: db_password 가 tfvars 에도 TF_VAR_db_password 에도 없습니다." >&2
  exit 1
fi

# ── 1단계: EKS cold-start ──────────────────────────────────────────
if ! kubectl cluster-info >/dev/null 2>&1 \
   || ! terraform state list 2>/dev/null | grep -q '^module\.eks\.'; then
  echo "==> [1/4] terraform apply -target=module.eks (cold-start)"
  terraform apply -auto-approve -target=module.network -target=module.eks
else
  echo "==> [1/4] EKS 이미 존재 — cold-start 단계 건너뜀"
fi

CLUSTER="$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")"
[ -z "$CLUSTER" ] && { echo "ERROR: eks_cluster_name output 없음"; exit 1; }
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
for i in {1..12}; do
  kubectl get ns >/dev/null 2>&1 && break
  echo "  클러스터 API 대기... ($i/12)"; sleep 5
done

# ── 2단계: ArgoCD + ALB controller + KEDA ────────────────────────
echo "==> [2/4] terraform apply -target=argocd,alb_controller,keda"
terraform apply -auto-approve \
  -target=module.argocd -target=module.alb_controller -target=module.keda

echo "  Application CRD 대기..."
for i in {1..24}; do
  kubectl get crd applications.argoproj.io >/dev/null 2>&1 && { echo "  CRD 확인"; break; }
  sleep 5
done

# ── 3단계: ArgoCD Application CR 생성 (동적) ─────────────────────
echo "==> [3/4] ArgoCD Application 생성 (Helm parameters 로 계정값 주입)"
ACCOUNT_ID="$(terraform output -raw aws_account_id)"
ECR_WAS="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ticketing/ticketing-was"
ECR_WORKER="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/ticketing/worker-svc"
SA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/ticketing-sqs-access-role"

# 기존 Application 에 이미 태그가 설정돼 있으면 보존 (seed.sh 로 push 된 실제 SHA).
# 없으면 seed-pending (이미지 없어도 Ingress 는 생성되어 ALB 프로비저닝은 진행됨).
EXISTING_TAG="$(kubectl -n argocd get application ticketing-prod \
  -o jsonpath='{range .spec.source.helm.parameters[?(@.name=="images.was.tag")]}{.value}{end}' \
  2>/dev/null || true)"
IMAGE_TAG="${EXISTING_TAG:-seed-pending}"
echo "  image tag: $IMAGE_TAG"

cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticketing-prod
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${K8S_REPO_URL}
    targetRevision: ${K8S_REPO_REVISION}
    path: charts/ticketing
    helm:
      releaseName: ticketing
      valueFiles:
        - ../../environments/prod/values.yaml
      parameters:
        - name: images.was.repository
          value: ${ECR_WAS}
        - name: images.was.tag
          value: ${IMAGE_TAG}
        - name: images.worker.repository
          value: ${ECR_WORKER}
        - name: images.worker.tag
          value: ${IMAGE_TAG}
        - name: serviceAccounts.sqs-access-sa.annotations.eks\.amazonaws\.com/role-arn
          value: ${SA_ROLE_ARN}
  destination:
    server: https://kubernetes.default.svc
    namespace: ticketing
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

echo "  Ingress 생성 대기 (ArgoCD sync 중)..."
for i in {1..60}; do
  kubectl get ingress -n ticketing 2>/dev/null | grep -q . && { echo "  Ingress 감지"; break; }
  echo "  [$i/60] ingress 대기..."
  sleep 10
done

# ── 4단계: 전체 apply ─────────────────────────────────────────────
echo "==> [4/4] terraform apply (전체)"
terraform apply -auto-approve

echo "==> apply 완료"
if [ "$IMAGE_TAG" = "seed-pending" ]; then
  echo ""
  echo "  이미지가 아직 ECR 에 없습니다. 다음 단계:"
  echo "    cd ../../soldesk-app && bash scripts/seed.sh"
  echo "  seed.sh 가 이미지를 push + Application tag 를 실제 SHA 로 patch 합니다."
fi
echo "  ArgoCD UI: kubectl port-forward -n argocd svc/argocd-server 8080:80"
echo "  초기 비밀번호: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
