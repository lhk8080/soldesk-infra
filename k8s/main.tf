data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

# IRSA role ARN은 compute 모듈에서 name_prefix = substr(cluster_name, 0, 32) 기준으로 생성됨
locals {
  name_prefix = substr(replace(var.cluster_name, "/[^a-zA-Z0-9+=,.@_-]/", "-"), 0, 32)
}

data "aws_iam_role" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-role"
}

data "aws_iam_role" "keda_operator" {
  name = "${local.name_prefix}-keda-operator-role"
}

data "aws_iam_role" "eso" {
  name = "${local.name_prefix}-eso-role"
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type = "gp3"
  }
}

module "alb_controller" {
  source = "../modules/kubernetes/addons/alb_controller"

  cluster_name = var.cluster_name
  aws_region   = var.aws_region
  vpc_id       = data.aws_eks_cluster.main.vpc_config[0].vpc_id
  role_arn      = data.aws_iam_role.alb_controller.arn
  chart_version = var.alb_controller_version
}

module "keda" {
  source = "../modules/kubernetes/addons/keda"

  cluster_name           = var.cluster_name
  aws_region             = var.aws_region
  keda_operator_role_arn = data.aws_iam_role.keda_operator.arn
  chart_version          = var.keda_version

  depends_on = [module.alb_controller]
}

module "eso" {
  source = "../modules/kubernetes/addons/eso"

  role_arn = data.aws_iam_role.eso.arn

  depends_on = [module.alb_controller]
}

module "argocd" {
  source = "../modules/kubernetes/gitops/argocd"

  chart_version = var.argocd_version
  domain_name   = var.domain_name
  waf_acl_arn   = var.waf_regional_acl_arn

  depends_on = [module.alb_controller]
}
