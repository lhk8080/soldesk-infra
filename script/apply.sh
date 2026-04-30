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

terraform apply -var-file="${INFRA_TFVARS}" -auto-approve

# ── 2. infra (2차): CloudFront domain → Cognito callback URL ─
echo ">>> [2/3] infra apply (pass 2: cloudfront_domain 갱신)"
CF_DOMAIN=$(terraform output -raw cloudfront_domain)
terraform apply \
  -var-file="${INFRA_TFVARS}" \
  -var="cloudfront_domain=${CF_DOMAIN}" \
  -auto-approve

CLUSTER_NAME=$(terraform output -raw cluster_name)

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

terraform apply -var-file="${K8S_TFVARS}" -auto-approve

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
  destination:
    server: https://kubernetes.default.svc
    namespace: dev-ticketing
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
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

# ── 완료 ─────────────────────────────────────────────────────
echo ""
echo "=== Apply 완료 ==="
echo ""
echo "[다음 단계] 앱 배포 후 API Gateway 연결:"
echo "  1. ArgoCD로 앱 배포 → ALB Controller가 ALB 생성"
echo "  2. ALB listener ARN 확인:"
echo "     aws elbv2 describe-listeners --load-balancer-arn \$(aws elbv2 describe-load-balancers --query 'LoadBalancers[0].LoadBalancerArn' --output text)"
echo "  3. infra/ 재apply:"
echo "     cd ${SCRIPT_DIR}/infra"
echo "     terraform apply -var-file=terraform.tfvars -var='cloudfront_domain=${CF_DOMAIN}' -var='alb_listener_arn=<ARN>' -auto-approve"
