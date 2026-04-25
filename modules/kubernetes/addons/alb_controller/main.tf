resource "helm_release" "alb_controller" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = var.namespace
  version          = var.version

  wait            = true
  timeout         = 300
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      clusterName       = var.cluster_name
      region            = var.aws_region
      vpcId             = var.vpc_id
      priorityClassName = "system-cluster-critical"
      replicaCount      = 1
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = var.role_arn
        }
      }
      resources = {
        requests = { cpu = "100m", memory = "200Mi" }
        limits   = { cpu = "100m", memory = "200Mi" }
      }
    })
  ]
}
