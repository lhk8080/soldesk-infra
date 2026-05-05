#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 필수 환경변수
: "${AWS_REGION:=ap-northeast-2}"

: "${TF_STATE_BUCKET:=sol-ticketing-tfstate}"
echo ">>> TF_STATE_BUCKET=${TF_STATE_BUCKET}"

INFRA_TFVARS="${SCRIPT_DIR}/infra/terraform.tfvars"
K8S_TFVARS="${SCRIPT_DIR}/k8s/terraform.tfvars"

# ── 1. infra (1차) ───────────────────────────────────────────
echo ">>> [1/3] infra apply (pass 1)"
cd "${SCRIPT_DIR}/infra"

terraform init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="key=infra/terraform.tfstate"

# 재실행 보존: state 에 이미 있는 alb_listener_arn 을 읽어 다시 주입
# (없으면 빈 문자열 — 첫 apply 때는 ALB 가 아직 없음)
EXISTING_LISTENER_ARN=$(terraform output -raw alb_listener_arn 2>/dev/null || true)
EXISTING_LISTENER_ARN="${EXISTING_LISTENER_ARN:-}"

# state 에 ARN 이 남아있어도 AWS 에 실재하지 않으면 비움 (stale state 방어)
# 안 비우면 API GW integration 이 죽은 listener 로 생성 시도 → 400 BadRequest
if [[ -n "${EXISTING_LISTENER_ARN}" ]]; then
  if aws elbv2 describe-listeners \
       --listener-arns "${EXISTING_LISTENER_ARN}" \
       --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo ">>> 기존 alb_listener_arn 보존: ${EXISTING_LISTENER_ARN}"
  else
    echo ">>> state 의 alb_listener_arn 이 AWS 에 없음 → 비우고 첫-실행 모드로 진행"
    EXISTING_LISTENER_ARN=""
  fi
fi

terraform apply -var-file="${INFRA_TFVARS}" \
  -var="alb_listener_arn=${EXISTING_LISTENER_ARN}" \
  -auto-approve

# ── 2. infra (2차): CloudFront domain → Cognito callback URL ─
echo ">>> [2/3] infra apply (pass 2: cloudfront_domain 갱신)"
CF_DOMAIN=$(terraform output -raw cloudfront_domain)
terraform apply \
  -var-file="${INFRA_TFVARS}" \
  -var="cloudfront_domain=${CF_DOMAIN}" \
  -var="alb_listener_arn=${EXISTING_LISTENER_ARN}" \
  -auto-approve

CLUSTER_NAME=$(terraform output -raw cluster_name)
DOMAIN_NAME=$(terraform output -raw domain_name)
WAF_REGIONAL_ARN=$(terraform output -raw waf_regional_acl_arn)

# ── 3. k8s addons ────────────────────────────────────────────
echo ">>> [3/3] k8s addons apply (EKS cluster 준비 대기 중...)"
aws eks wait cluster-active \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}"

# kubeconfig 갱신 — 이전 클러스터 endpoint 가 남아있을 경우 새 클러스터로 전환
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

cd "${SCRIPT_DIR}/k8s"

terraform init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="key=k8s/terraform.tfstate"

terraform apply -var-file="${K8S_TFVARS}" \
  -var="domain_name=${DOMAIN_NAME}" \
  -var="waf_regional_acl_arn=${WAF_REGIONAL_ARN}" \
  -auto-approve

# ── 4. ArgoCD Application 등록 ───────────────────────────────
echo ">>> [4/4] ArgoCD Application 등록"
cd "${SCRIPT_DIR}/infra"

ECR_WAS_URL=$(terraform output -raw ecr_ticketing_was_url)
ECR_WORKER_URL=$(terraform output -raw ecr_worker_svc_url)
SQS_ACCESS_ROLE_ARN=$(terraform output -raw sqs_access_role_arn)
DB_BACKUP_ROLE_ARN=$(terraform output -raw db_backup_role_arn)
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn)
SQS_QUEUE_URL=$(terraform output -raw sqs_reservation_url)
SQS_QUEUE_URL_DEV=$(terraform output -raw sqs_reservation_url_dev)
ASSETS_BUCKET=$(terraform output -raw assets_bucket_id)

# ArgoCD server 준비 대기
kubectl wait --namespace argocd \
  --for=condition=Ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s

# image.was.tag, image.worker.tag 는 environments/<env>/ticketing-values.yaml 이 source of truth
# (GHA 가 빌드 후 sed + commit + push 로 갱신 → ArgoCD 자동 sync)

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticketing
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    notifications.argoproj.io/subscribe.on-deployed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-sync-failed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-health-degraded.slack-deploys: ""
spec:
  project: default
  source:
    repoURL: https://github.com/lhk8080/soldesk-k8s.git
    targetRevision: HEAD
    path: charts/ticketing
    helm:
      valueFiles:
        - ../../environments/prod/ticketing-values.yaml
      parameters:
        - name: image.was.repository
          value: "${ECR_WAS_URL}"
        - name: image.worker.repository
          value: "${ECR_WORKER_URL}"
        - name: serviceAccount.sqsAccessRoleArn
          value: "${SQS_ACCESS_ROLE_ARN}"
        - name: serviceAccount.dbBackupRoleArn
          value: "${DB_BACKUP_ROLE_ARN}"
        - name: config.sqsQueueUrl
          value: "${SQS_QUEUE_URL}"
        - name: backup.s3Bucket
          value: "${ASSETS_BUCKET}"
  destination:
    server: https://kubernetes.default.svc
    namespace: ticketing
  # HPA(KEDA) 가 관리하는 burst Deployment 의 replicas 는 ArgoCD 가 드리프트로 보지 않음.
  # 안 그러면 selfHeal 이 차트 기준값으로 되돌려 HPA 와 충돌(0↔N oscillation) 발생.
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: worker-svc-burst
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      name: read-api-burst
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      name: write-api-burst
      jsonPointers:
        - /spec/replicas
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ticketing-dev
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "10"
    notifications.argoproj.io/subscribe.on-deployed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-sync-failed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-health-degraded.slack-deploys: ""
spec:
  project: default
  source:
    repoURL: https://github.com/lhk8080/soldesk-k8s.git
    targetRevision: HEAD
    path: charts/ticketing
    helm:
      valueFiles:
        - ../../environments/dev/ticketing-values.yaml
      parameters:
        - name: image.was.repository
          value: "${ECR_WAS_URL}"
        - name: image.worker.repository
          value: "${ECR_WORKER_URL}"
        - name: serviceAccount.sqsAccessRoleArn
          value: "${SQS_ACCESS_ROLE_ARN}"
        - name: serviceAccount.dbBackupRoleArn
          value: "${DB_BACKUP_ROLE_ARN}"
        - name: config.sqsQueueUrl
          value: "${SQS_QUEUE_URL_DEV}"
        - name: ingress.host
          value: "dev.${DOMAIN_NAME}"
        - name: ingress.wafAclArn
          value: "${WAF_REGIONAL_ARN}"
  destination:
    server: https://kubernetes.default.svc
    namespace: dev-ticketing
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: worker-svc-burst
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      name: read-api-burst
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      name: write-api-burst
      jsonPointers:
        - /spec/replicas
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
    notifications.argoproj.io/subscribe.on-deployed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-sync-failed.slack-deploys: ""
    notifications.argoproj.io/subscribe.on-health-degraded.slack-deploys: ""
spec:
  project: default
  source:
    repoURL: https://github.com/lhk8080/soldesk-k8s.git
    targetRevision: HEAD
    path: charts/monitoring
    helm:
      valueFiles:
        - ../../environments/prod/monitoring-values.yaml
      parameters:
        - name: esoRoleArn
          value: "${ESO_ROLE_ARN}"
        - name: awsRegion
          value: "${AWS_REGION}"
        - name: grafana.host
          value: "grafana.${DOMAIN_NAME}"
        - name: grafana.wafAclArn
          value: "${WAF_REGIONAL_ARN}"
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  # ESO 가 admission 시점에 채우는 default 필드 (conversionStrategy 등) 가
  # selfHeal 과 충돌해 무한 sync 루프를 일으키므로 무시한다.
  ignoreDifferences:
    - group: external-secrets.io
      kind: ExternalSecret
      jsonPointers:
        - /spec/data/0/remoteRef/conversionStrategy
        - /spec/data/0/remoteRef/decodingStrategy
        - /spec/data/0/remoteRef/metadataPolicy
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

# ── 5. ALB listener 자동 연결 (apply-alb.sh 인라인) ──────────
echo ""
echo ">>> [5/5] ticketing(prod) ALB 생성 대기 후 listener ARN 주입"
"${SCRIPT_DIR}/script/apply-alb.sh"

# ── 완료 ─────────────────────────────────────────────────────
echo ""
echo "=== Apply 완료 ==="
echo ""
echo "[다음 단계] Ops 도메인(argocd / grafana / dev) Route53 등록:"
echo "  ${SCRIPT_DIR}/script/seed-ops-dns.sh"
echo "  (ArgoCD 가 ops Ingress 들을 sync 한 뒤 실행)"
