#!/bin/bash
# ArgoCD 가 ticketing 앱을 sync 해서 ALB Controller 가 ALB 를 만든 뒤,
# 그 ALB 의 listener ARN 을 찾아 infra 의 terraform 에 넣어 재apply 한다.
# (cloudfront_domain 은 이미 1차 apply 에서 output 으로 자동 주입됨)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/../infra" && pwd)"
INFRA_TFVARS="${INFRA_DIR}/terraform.tfvars"

: "${AWS_REGION:=ap-northeast-2}"
: "${INGRESS_NAMESPACE:=ticketing}"
: "${INGRESS_NAME:=ticketing-ingress}"
: "${WAIT_TIMEOUT:=600}"  # ALB 생성까지 최대 10분 대기

echo ">>> Ingress 가 ALB 를 띄울 때까지 대기 (${INGRESS_NAMESPACE}/${INGRESS_NAME})"
elapsed=0
ALB_HOSTNAME=""
while [ "${elapsed}" -lt "${WAIT_TIMEOUT}" ]; do
  ALB_HOSTNAME=$(kubectl get ingress "${INGRESS_NAME}" -n "${INGRESS_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "${ALB_HOSTNAME}" ]; then
    break
  fi
  sleep 10
  elapsed=$((elapsed + 10))
  echo "    ... 대기중 (${elapsed}s)"
done

if [ -z "${ALB_HOSTNAME}" ]; then
  echo "ERROR: ${WAIT_TIMEOUT}s 동안 ALB hostname 을 못 찾음" >&2
  exit 1
fi
echo ">>> ALB hostname: ${ALB_HOSTNAME}"

# ALB hostname → ALB ARN → listener ARN
# ALB hostname 형식: <name>-<id>.<region>.elb.amazonaws.com
ALB_NAME="${ALB_HOSTNAME%%-[0-9]*}"  # 첫 번째 '-숫자' 직전까지
# 위 trick 이 불안하면 DNSName 으로 직접 매칭
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --query "LoadBalancers[?DNSName=='${ALB_HOSTNAME}'].LoadBalancerArn | [0]" \
  --output text)

if [ -z "${ALB_ARN}" ] || [ "${ALB_ARN}" = "None" ]; then
  echo "ERROR: ALB ARN 조회 실패 (hostname=${ALB_HOSTNAME})" >&2
  exit 1
fi
echo ">>> ALB ARN: ${ALB_ARN}"

# HTTPS(443) listener 우선, 없으면 첫 번째
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --region "${AWS_REGION}" \
  --load-balancer-arn "${ALB_ARN}" \
  --query "Listeners[?Port==\`443\`].ListenerArn | [0]" \
  --output text)

if [ -z "${LISTENER_ARN}" ] || [ "${LISTENER_ARN}" = "None" ]; then
  LISTENER_ARN=$(aws elbv2 describe-listeners \
    --region "${AWS_REGION}" \
    --load-balancer-arn "${ALB_ARN}" \
    --query "Listeners[0].ListenerArn" \
    --output text)
fi

if [ -z "${LISTENER_ARN}" ] || [ "${LISTENER_ARN}" = "None" ]; then
  echo "ERROR: listener ARN 조회 실패" >&2
  exit 1
fi
echo ">>> Listener ARN: ${LISTENER_ARN}"

# CloudFront domain 은 1차 apply 결과물에서 가져옴
cd "${INFRA_DIR}"
CF_DOMAIN=$(terraform output -raw cloudfront_domain)
echo ">>> CloudFront domain: ${CF_DOMAIN}"

echo ">>> infra terraform apply (alb_listener_arn 주입)"
terraform apply \
  -var-file="${INFRA_TFVARS}" \
  -var="cloudfront_domain=${CF_DOMAIN}" \
  -var="alb_listener_arn=${LISTENER_ARN}" \
  -auto-approve

echo ""
echo "=== ALB 연결 완료 ==="
