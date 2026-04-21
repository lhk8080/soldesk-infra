# 모든 런타임 시크릿/설정값을 SSM Parameter Store(SecureString)로 관리.
# ESO(External Secrets Operator)가 IRSA로 GetParameter 후 K8s Secret으로 머티리얼라이즈.
#
# 경로 컨벤션: /<app>/<env>/<카테고리>/<키>
#   ESO ExternalSecret의 dataFrom.find.path 와 IAM 정책의 Resource ARN이 모두 이 prefix에 의존.
#
# 모든 파라미터를 SecureString으로 통일 → 평문/암호 구분 없이 IAM/감사 일관성 확보.

terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Grafana admin 비번은 모듈이 직접 생성 → SSM SecureString으로 저장 → kube-prometheus-stack
# Helm values 의 grafana.admin.existingSecret 으로 주입 (ESO가 K8s Secret으로 머티리얼라이즈).
resource "random_password" "grafana_admin" {
  length           = 20
  special          = true
  override_special = "!#$%^&*()-_=+"
}

locals {
  prefix = "/${var.app_name}/${var.env}"

  cognito_issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  cognito_jwks_uri = "${local.cognito_issuer}/.well-known/jwks.json"

  parameters = {
    "db/password"           = var.db_password
    "db/writer_host"        = var.db_writer_host
    "db/reader_host"        = var.db_reader_host
    "db/user"               = var.db_user
    "redis/host"            = var.redis_host
    "sqs/queue_url"         = var.sqs_queue_url
    "sqs/ui_queue_url"      = var.sqs_queue_interactive_url
    "cognito/client_id"     = var.cognito_app_client_id
    "cognito/issuer"        = local.cognito_issuer
    "cognito/jwks_uri"      = local.cognito_jwks_uri
    "grafana/admin_user"    = "admin"
    "grafana/admin_password" = random_password.grafana_admin.result
  }
}

# Alertmanager Slack webhook — 별도 resource 로 분리한 이유:
#   1) SSM SecureString 은 빈 값 거부 → 미입력 시 placeholder 사용
#   2) 운영자가 aws ssm put-parameter 로 실값 주입 후, terraform apply 가 placeholder 로
#      되돌리지 않도록 lifecycle ignore_changes 로 value 변경 무시.
resource "aws_ssm_parameter" "alertmanager_slack_webhook" {
  name  = "${local.prefix}/alertmanager/slack_webhook"
  type  = "SecureString"
  value = var.alertmanager_slack_webhook != "" ? var.alertmanager_slack_webhook : "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Application = var.app_name
    Environment = var.env
    ManagedBy   = "terraform"
  }
}

resource "aws_ssm_parameter" "this" {
  for_each = local.parameters

  name  = "${local.prefix}/${each.key}"
  type  = "SecureString"
  value = each.value

  tags = {
    Application = var.app_name
    Environment = var.env
    ManagedBy   = "terraform"
  }
}
