# EBS CSI Driver — Grafana/Prometheus PVC(gp3) 프로비저닝에 필요.
# 없으면 StorageClass ebs.csi.aws.com 이 WaitForFirstConsumer → 영구 Pending.
resource "aws_iam_role" "ebs_csi" {
  name = "${local.name_prefix}-ebs-csi-driver-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  configuration_values = jsonencode({
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "200Mi" }
        limits   = { cpu = "100m", memory = "200Mi" }
      }
    }
    node = {
      resources = {
        requests = { cpu = "50m", memory = "100Mi" }
        limits   = { cpu = "50m", memory = "100Mi" }
      }
    }
  })

  depends_on = [
    aws_eks_node_group.app,
    aws_iam_role_policy_attachment.ebs_csi,
  ]

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
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
  depends_on = [aws_eks_addon.ebs_csi]
}
