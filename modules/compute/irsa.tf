# ── ALB Controller ─────────────────────────────────────────────────────────
resource "aws_iam_policy" "alb_controller" {
  name   = "${local.name_prefix}-alb-controller-policy"
  policy = file("${path.module}/alb-controller-policy.json")
}

resource "aws_iam_role" "alb_controller" {
  name = "${local.name_prefix}-alb-controller-role"
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
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ── Cluster Autoscaler ─────────────────────────────────────────────────────
resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${local.name_prefix}-cluster-autoscaler-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeInstanceTypes",
        "eks:DescribeNodegroup",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.name_prefix}-cluster-autoscaler-role"
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
          "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# ── SQS Access (reserv-svc, worker-svc 공용) ───────────────────────────────
resource "aws_iam_role" "sqs_access" {
  name = "${local.name_prefix}-sqs-access-role"
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
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = [
            "system:serviceaccount:ticketing:sqs-access-sa",
            "system:serviceaccount:dev-ticketing:sqs-access-sa",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "sqs_access" {
  name = "${local.name_prefix}-sqs-access-policy"
  role = aws_iam_role.sqs_access.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:GetQueueAttributes",
      ]
      Resource = var.sqs_queue_arns
    }]
  })
}

# ── DB Backup CronJob ──────────────────────────────────────────────────────
# mysqldump 결과를 assets 버킷 backups/ prefix 에 PutObject
resource "aws_iam_role" "db_backup" {
  name = "${local.name_prefix}-db-backup-role"
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
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = [
            "system:serviceaccount:ticketing:db-backup-sa",
            "system:serviceaccount:dev-ticketing:db-backup-sa",
          ]
        }
      }
    }]
  })
}

# assets_bucket_arn 이 plan 시점 unknown 이 될 수 있어 bool 플래그로 count 분기
resource "aws_iam_role_policy" "db_backup" {
  count = var.enable_db_backup_to_assets ? 1 : 0
  name  = "${local.name_prefix}-db-backup-policy"
  role  = aws_iam_role.db_backup.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
      Resource = "${var.assets_bucket_arn}/backups/*"
    }]
  })
}

# ── ESO (External Secrets Operator) ───────────────────────────────────────
resource "aws_iam_role" "eso" {
  name = "${local.name_prefix}-eso-role"
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
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso" {
  name = "${local.name_prefix}-eso-policy"
  role = aws_iam_role.eso.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:*"
      },
    ]
  })
}

# ── KEDA Operator ──────────────────────────────────────────────────────────
# KEDA operator Pod 가 SQS GetQueueAttributes 로 스케일 메트릭 조회 (ScaledObject aws-sqs-queue)
# TriggerAuthentication identityOwner=keda 일 때 이 역할이 사용됨
resource "aws_iam_role" "keda_operator" {
  name = "${local.name_prefix}-keda-operator-role"
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
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          "${local.oidc_issuer}:sub" = "system:serviceaccount:keda:keda-operator"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "keda_operator_sqs_read" {
  name = "${local.name_prefix}-keda-operator-sqs-read"
  role = aws_iam_role.keda_operator.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
      ]
      Resource = var.sqs_queue_arns
    }]
  })
}
