locals {
  name_prefix  = substr(replace(var.cluster_name, "/[^a-zA-Z0-9+=,.@_-]/", "-"), 0, 32)
  oidc_issuer  = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

data "aws_caller_identity" "current" {}

# ── EKS Cluster IAM ────────────────────────────────────────────────────────
data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Cluster ────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.30"

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster,
    null_resource.cleanup_vpc_leftovers_post,
  ]

  tags = { Name = var.cluster_name, Environment = var.env }
}

# ── OIDC Provider ──────────────────────────────────────────────────────────
# apply 시점의 실제 cert fingerprint 를 동적 조회 — AWS 갱신 시 하드코딩 값 stale 방지
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

# ── Worker Node IAM ────────────────────────────────────────────────────────
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── vpc-cni Addon ──────────────────────────────────────────────────────────
# ENABLE_PREFIX_DELEGATION + VPC Custom Networking 조합:
#   - prefix delegation: ENI 1개가 /28(16 IP) 단위로 파드 밀도↑
#   - custom networking: 파드 IP 를 secondary CIDR(100.64.0.0/16)에서 받아 노드 subnet IP 고갈 차단
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    env = {
      ENABLE_PREFIX_DELEGATION           = "true"
      WARM_PREFIX_TARGET                 = "1"
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
      ENI_CONFIG_LABEL_DEF               = "topology.kubernetes.io/zone"
    }
  })

  depends_on = [aws_eks_cluster.main]
}

# ENIConfig (AZ 당 1개) — vpc-cni 이후, 노드그룹 이전에 반드시 적용되어야 함.
# custom networking 켜진 상태에서 ENIConfig 없이 노드가 올라오면 ipamd 초기화 실패 → NodeCreationFailure.
resource "null_resource" "pod_eni_configs" {
  triggers = {
    cluster_name = aws_eks_cluster.main.name
    region       = var.aws_region
    payload_hash = md5(jsonencode({
      subnets = var.pod_subnet_ids
      azs     = var.pod_subnet_azs
      sgs = [
        var.security_group_id,
        aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
      ]
    }))
  }

  depends_on = [aws_eks_addon.vpc_cni]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      CLUSTER_NAME   = aws_eks_cluster.main.name
      AWS_REGION     = var.aws_region
      POD_SUBNET_IDS = join(",", var.pod_subnet_ids)
      POD_SUBNET_AZS = join(",", var.pod_subnet_azs)
      POD_SG_IDS = join(",", [
        var.security_group_id,
        aws_eks_cluster.main.vpc_config[0].cluster_security_group_id,
      ])
      AWS_PAGER = ""
    }
    command = "tr -d '\\r' < \"${path.module}/scripts/apply_eni_configs.sh\" | bash"
  }
}

# ── Worker Node Group ──────────────────────────────────────────────────────
resource "aws_eks_node_group" "app" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-app-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.app_node_instance_types
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.app_node_desired_size
    min_size     = var.app_node_min_size
    max_size     = var.app_node_max_size
  }

  update_config { max_unavailable = 1 }

  labels = { role = "app" }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_eks_addon.vpc_cni,
    null_resource.pod_eni_configs,
    null_resource.cleanup_vpc_leftovers_post,
  ]

  # Cluster Autoscaler autoDiscovery 에 필요한 ASG 태그
  tags = merge(
    {
      Name        = "${local.name_prefix}-app-nodes"
      Environment = var.env
    },
    {
      "k8s.io/cluster-autoscaler/enabled"             = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    }
  )
}

# ── metrics-server Addon ───────────────────────────────────────────────────
# HPA(Resource)가 cpu/memory utilization 을 받으려면 metrics.k8s.io API 가 필요
data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.metrics_server.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    resources = {
      requests = { cpu = "100m", memory = "200Mi" }
      limits   = { cpu = "100m", memory = "200Mi" }
    }
  })

  depends_on = [aws_eks_node_group.app]
}
