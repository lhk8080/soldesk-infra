# External Secrets Operator용 IRSA role.
# ESO 차트 자체는 ArgoCD App-of-Apps(soldesk-k8s/argocd/platform)로 설치한다.
# 여기서는 IAM/IRSA만 만든다 (terraform이 K8s helm 설치까지는 안 함 → GitOps 영역).
#
# 신뢰 주체: ticketing 네임스페이스의 ServiceAccount(`ticketing-eso-sa`).
# ESO의 SecretStore가 spec.provider.aws.auth.jwt.serviceAccountRef로 이 SA를 참조하면
# ESO 컨트롤러 Pod(external-secrets ns)가 해당 SA의 토큰으로 STS AssumeRoleWithWebIdentity 호출.
# → 즉, ESO 컨트롤러는 external-secrets ns에 있어도, 권한 컨텍스트는 ticketing ns의 SA.

data "aws_caller_identity" "current" {}

locals {
  eso_sa_subjects = concat(
    ["system:serviceaccount:${var.ticketing_namespace}:${var.eso_service_account}"],
    var.extra_service_account_subjects,
  )
}

resource "aws_iam_role" "eso" {
  name = "${var.app_name}-external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
        "ForAnyValue:StringEquals" = {
          "${var.oidc_issuer}:sub" = local.eso_sa_subjects
        }
      }
    }]
  })

  tags = {
    Application = var.app_name
    Environment = var.env
  }
}

# SSM SecureString을 읽으려면 ssm:GetParameter* + 기본 KMS key의 Decrypt 가 필요.
# alias/aws/ssm은 계정/리전 기본 SSM key. 별도 CMK 사용 시 그 ARN으로 교체.
resource "aws_iam_role_policy" "eso_ssm" {
  name = "${var.app_name}-external-secrets-ssm"
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
          "ssm:DescribeParameters",
        ]
        # /ticketing/prod/* 만 허용. SSM ARN은 path 앞 "/" 가 ARN 안에서는 제거됨에 주의.
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_prefix}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}
