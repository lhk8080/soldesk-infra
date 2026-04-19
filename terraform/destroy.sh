#!/usr/bin/env bash
# Terraform destroy 래퍼:
# ArgoCD/앱이 만든 Ingress/LB Service를 먼저 정리해서 ALB·SG·ENI 고아를 막음.
# 실패해도 계속 진행(|| true): EKS가 이미 없는 상태에서도 안전하게 동작.
set -euo pipefail
cd "$(dirname "$0")"

REGION=ap-northeast-2
CLUSTER=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")

if [ -n "$CLUSTER" ]; then
  echo "==> kubeconfig 갱신 ($CLUSTER)"
  aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null 2>&1 || true

  if kubectl cluster-info >/dev/null 2>&1; then
    echo "==> ArgoCD Application finalizer 제거 후 삭제"
    kubectl get applications.argoproj.io -A -o name 2>/dev/null | while read r; do
      ns=$(echo "$r" | awk -F/ '{print $1}')
      kubectl patch "$r" -n argocd --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
    done
    kubectl delete applications.argoproj.io --all -A --wait=false --ignore-not-found || true
    kubectl delete appprojects.argoproj.io --all -A --wait=false --ignore-not-found || true

    echo "==> Ingress / LB Service 삭제 (ALB·NLB 제거 유도)"
    kubectl delete ingress --all -A --wait=false --ignore-not-found || true
    kubectl get svc -A --no-headers 2>/dev/null \
      | awk '$5=="LoadBalancer"{print $1" "$2}' \
      | while read ns name; do
          kubectl delete svc -n "$ns" "$name" --wait=false --ignore-not-found || true
        done

    echo "==> finalizer 제거 (걸려 있으면)"
    kubectl get ns --no-headers -o custom-columns=:metadata.name 2>/dev/null | while read ns; do
      kubectl get ingress,svc -n "$ns" -o name 2>/dev/null | while read r; do
        kubectl patch "$r" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
      done
    done

    echo "==> TargetGroupBinding finalizer 제거 (ALB Controller가 먼저 사라진 경우 대비)"
    if kubectl api-resources 2>/dev/null | grep -q targetgroupbindings; then
      kubectl get targetgroupbinding.elbv2.k8s.aws -A -o json 2>/dev/null \
        | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' \
        | while read ns name; do
            [ -z "$ns" ] && continue
            kubectl patch targetgroupbinding.elbv2.k8s.aws "$name" -n "$ns" \
              --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
            kubectl delete targetgroupbinding.elbv2.k8s.aws "$name" -n "$ns" \
              --wait=false --ignore-not-found >/dev/null 2>&1 || true
          done
    fi

    echo "==> 모든 namespace의 Terminating 강제 해제"
    kubectl get ns --no-headers 2>/dev/null | awk '$2=="Terminating"{print $1}' | while read ns; do
      echo "  - $ns finalize"
      kubectl get ns "$ns" -o json 2>/dev/null \
        | jq '.spec.finalizers=[] | .metadata.finalizers=[]' \
        | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - >/dev/null 2>&1 || true
    done

  else
    echo "==> 클러스터 접근 불가 — k8s 정리 건너뜀"
  fi
fi

if [ -n "$VPC_ID" ]; then
  echo "==> AWS LB 정리 대기 (최대 90초)"
  for i in {1..18}; do
    LEFT=$(aws elbv2 describe-load-balancers --region "$REGION" \
      --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
      --output text 2>/dev/null || echo "")
    [ -z "$LEFT" ] && { echo "  모든 LB 삭제됨"; break; }
    echo "  남은 LB 있음, 대기 중..."
    sleep 5
  done
fi

# data source 는 destroy 시점에도 refresh 되는데, ALB 를 위에서 이미 지웠으므로
# aws_lb lookup 이 0 results 로 실패함. state 에서 제거하여 refresh 생략.
echo "==> ALB data source state 제거 (ALB 이미 삭제됨)"
terraform state rm \
  module.api_gateway.data.aws_lb.ingress \
  module.api_gateway.data.aws_lb_listener.ingress 2>/dev/null || true

echo "==> terraform destroy"
terraform destroy -auto-approve -refresh=false

echo "==> ArgoCD CRD 정리 (terraform destroy 이후, 클러스터 남아있을 때만)"
if kubectl cluster-info >/dev/null 2>&1; then
  kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io --ignore-not-found --wait=false || true
fi
