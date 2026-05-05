# Cluster Autoscaler — Pending pod 감지해 ASG desired_capacity 를 늘려 노드를 추가한다.
# - autoDiscovery: ASG 의 k8s.io/cluster-autoscaler/{enabled, <cluster_name>=owned} 태그로 노드 그룹 자동 인식
# - IRSA: SA(kube-system:cluster-autoscaler) → ...-cluster-autoscaler-role
resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  namespace        = var.namespace
  create_namespace = false
  version          = var.chart_version

  wait            = true
  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = var.cluster_name
      }
      awsRegion = var.aws_region

      rbac = {
        serviceAccount = {
          create = true
          name   = "cluster-autoscaler"
          annotations = {
            "eks.amazonaws.com/role-arn" = var.role_arn
          }
        }
      }

      # 시스템 컴포넌트로 우선순위 부여 (자원 압박 시 evict 마지막 순위)
      priorityClassName = "system-cluster-critical"

      # 운영 권장값
      extraArgs = {
        "balance-similar-node-groups"      = true
        "skip-nodes-with-system-pods"      = false
        "scale-down-utilization-threshold" = 0.5
        "scale-down-unneeded-time"         = "5m"
        "expander"                         = "least-waste"
      }

      resources = {
        requests = { cpu = "100m", memory = "300Mi" }
        limits   = { cpu = "100m", memory = "300Mi" }
      }
    })
  ]
}
