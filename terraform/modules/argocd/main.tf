terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# ArgoCD 설치만 담당. Application(루트/하위 앱) 등록은 GitOps 진입점이므로
# Terraform 밖에서 `kubectl apply -f` 로 부트스트랩한다 (apply.sh 참고).
# kubernetes_manifest 를 쓰면 plan 단계에 클러스터+CRD 가 이미 있어야 하므로
# cold-start 시 닭-달걀 문제가 발생 → 의도적으로 분리.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600

  values = var.values != "" ? [var.values] : []
}
