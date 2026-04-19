terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# ticketing 네임스페이스는 ArgoCD가 차트 sync 시 CreateNamespace=true 옵션으로 만든다.
# 단, Secret/ConfigMap은 파드 시작 전에 필요하므로 여기서 선제 생성.
resource "kubernetes_namespace" "ticketing" {
  metadata {
    name = var.namespace
  }
  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

locals {
  cognito_issuer    = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  cognito_jwks_uri  = "${local.cognito_issuer}/.well-known/jwks.json"
}

# 민감 정보: DB 비번, 엔드포인트, SQS URL 등
resource "kubernetes_secret" "ticketing" {
  metadata {
    name      = var.secret_name
    namespace = kubernetes_namespace.ticketing.metadata[0].name
  }

  # ConfigMap(ticketing-config)은 Helm 차트가 관리하므로 여기서 생성하지 않는다.
  # 인프라 output 기반 값(엔드포인트/비번/큐 URL/Cognito)만 Secret으로 주입.
  # DB_USER/COGNITO_APP_CLIENT_ID 등은 엄밀히 비민감이지만, 주입 채널 단일화를 위해 함께 담는다.
  data = {
    DB_WRITER_HOST               = var.db_writer_host
    DB_READER_HOST               = var.db_reader_host
    DB_USER                      = var.db_user
    DB_PASSWORD                  = var.db_password
    ELASTICACHE_PRIMARY_ENDPOINT = var.redis_host
    REDIS_HOST                   = var.redis_host
    ELASTICACHE_PORT             = tostring(var.redis_port)
    SQS_QUEUE_URL                = var.sqs_queue_url
    SQS_QUEUE_INTERACTIVE_URL    = var.sqs_queue_interactive_url
    COGNITO_APP_CLIENT_ID        = var.cognito_app_client_id
    COGNITO_ISSUER               = local.cognito_issuer
    COGNITO_JWKS_URI             = local.cognito_jwks_uri
  }

  type = "Opaque"
}
