#!/bin/bash
# argocd / grafana 서브도메인을 IngressGroup ALB 로 alias 등록
# apply.sh 가 끝난 뒤 1회 실행하면 됨 (ALB 가 한 번 만들어진 후엔 DNS 변경 불필요)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${AWS_REGION:=ap-northeast-2}"
: "${INGRESS_GROUP:=soldesk-ops}"

# ── 1. infra output 에서 도메인 읽기 ──────────────────────────
cd "${SCRIPT_DIR}/infra"
DOMAIN_NAME=$(terraform output -raw domain_name)
echo ">>> 도메인: ${DOMAIN_NAME}"

ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "${DOMAIN_NAME}." \
  --query "HostedZones[0].Id" --output text | sed 's|/hostedzone/||')
echo ">>> Route53 zone: ${ZONE_ID}"

# ── 2. IngressGroup ALB DNS 조회 (Ingress status 기반) ───────
echo ">>> argocd-server Ingress 의 ALB DNS 대기..."
for i in $(seq 1 60); do
  ALB_DNS=$(kubectl -n argocd get ingress argocd-server \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB_DNS}" ]]; then
    break
  fi
  echo "  ... ${i}/60 (10초 후 재시도)"
  sleep 10
done

if [[ -z "${ALB_DNS}" ]]; then
  echo "ERROR: argocd-server Ingress 에 ALB DNS 가 잡히지 않음" >&2
  echo "  kubectl get ingress -A 로 상태 확인" >&2
  exit 1
fi

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].CanonicalHostedZoneId | [0]" \
  --output text)

echo ">>> ALB DNS: ${ALB_DNS}"
echo ">>> ALB zone: ${ALB_ZONE_ID}"

# ── 3. Route53 alias 레코드 UPSERT ────────────────────────────
upsert_record() {
  local sub=$1
  echo ">>> UPSERT ${sub}.${DOMAIN_NAME} → ${ALB_DNS}"
  aws route53 change-resource-record-sets --hosted-zone-id "${ZONE_ID}" \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${sub}.${DOMAIN_NAME}\",
          \"Type\": \"A\",
          \"AliasTarget\": {
            \"HostedZoneId\": \"${ALB_ZONE_ID}\",
            \"DNSName\": \"${ALB_DNS}\",
            \"EvaluateTargetHealth\": false
          }
        }
      }]
    }" >/dev/null
}

upsert_record argocd
upsert_record grafana
upsert_record dev

echo ""
echo "=== 완료 ==="
echo "  http://argocd.${DOMAIN_NAME}  (HTTP 80, 현재 HTTPS 미적용)"
echo "  http://grafana.${DOMAIN_NAME}"
echo "  http://dev.${DOMAIN_NAME}"
echo ""
echo "DNS 전파에 1~2분 정도 소요됩니다."
