# PriorityClass는 KEDA보다 먼저 적용되어야 함 (KEDA chart에서 system-cluster-critical 참조)
# 앱 파드도 이 PriorityClass를 사용하므로 여기서 함께 관리
resource "null_resource" "priority_classes" {
  triggers = {
    cluster_name  = var.cluster_name
    manifest_hash = filemd5("${path.module}/manifests/priorityclass-ticketing.yaml")
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      CLUSTER_NAME = var.cluster_name
      AWS_REGION   = var.aws_region
      AWS_PAGER    = ""
    }
    command = <<-EOT
      set -euo pipefail
      _K="$(mktemp)"
      trap 'rm -f "$_K"' EXIT
      aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" --kubeconfig "$_K"
      export KUBECONFIG="$_K"
      kubectl apply -f "${path.module}/manifests/priorityclass-ticketing.yaml"
    EOT
  }
}

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = var.namespace
  create_namespace = true
  version          = var.chart_version

  wait            = true
  timeout         = 180
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      priorityClassName = "system-cluster-critical"
      serviceAccount = {
        create = true
        name   = "keda-operator"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.keda_operator_role_arn
        }
      }
      resources = {
        requests = { cpu = "200m", memory = "300Mi" }
        limits   = { cpu = "200m", memory = "300Mi" }
      }
      metricsServer = {
        resources = {
          requests = { cpu = "100m", memory = "150Mi" }
          limits   = { cpu = "100m", memory = "150Mi" }
        }
      }
      webhooks = {
        resources = {
          requests = { cpu = "50m", memory = "100Mi" }
          limits   = { cpu = "50m", memory = "100Mi" }
        }
      }
    })
  ]

  depends_on = [null_resource.priority_classes]
}

# destroy 시 KEDA webhook/secret/finalizer 잔재 정리
# 없으면 다음 apply에서 "cannot re-use a name that is still in use" 에러 발생
resource "null_resource" "keda_cleanup_on_destroy" {
  triggers = {
    cluster_name = var.cluster_name
    aws_region   = var.aws_region
    script_md5   = filemd5("${path.module}/scripts/keda_cleanup_on_destroy.sh")
  }

  depends_on = [helm_release.keda]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    when        = destroy
    environment = {
      CLUSTER_NAME                    = self.triggers.cluster_name
      AWS_REGION                      = self.triggers.aws_region
      KEDA_NAMESPACE                  = "keda"
      KEDA_RELEASE_NAME               = "keda"
      KEDA_CLEANUP_WAIT_SEC           = "120"
      KEDA_FORCE_REMOVE_FINALIZERS    = "1"
      KEDA_FORCE_FINALIZERS_AFTER_SEC = "20"
      AWS_PAGER                       = ""
    }
    command = "tr -d '\\r' < \"${path.module}/scripts/keda_cleanup_on_destroy.sh\" | bash"
  }
}
