terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

# KEDA: ticketing 차트의 ScaledObject/TriggerAuthentication이 의존하는 CRD 제공.
# ArgoCD 루트 App이 ticketing 차트를 동기화하기 전에 설치되어 있어야 함.
resource "helm_release" "keda" {
  name             = "keda"
  namespace        = var.namespace
  create_namespace = true

  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 600
}
