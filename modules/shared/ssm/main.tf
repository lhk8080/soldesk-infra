locals {
  prefix = "/${var.app_name}/prod"
}

resource "aws_ssm_parameter" "db_writer_host" {
  name  = "${local.prefix}/DB_WRITER_HOST"
  type  = "String"
  value = var.db_writer_endpoint
}

resource "aws_ssm_parameter" "db_reader_host" {
  name  = "${local.prefix}/DB_READER_HOST"
  type  = "String"
  value = var.db_reader_endpoint
}

resource "aws_ssm_parameter" "db_user" {
  name  = "${local.prefix}/DB_USER"
  type  = "String"
  value = var.db_user
}

resource "aws_ssm_parameter" "db_password" {
  name  = "${local.prefix}/DB_PASSWORD"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "elasticache_primary_endpoint" {
  name  = "${local.prefix}/ELASTICACHE_PRIMARY_ENDPOINT"
  type  = "String"
  value = var.redis_endpoint
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "${local.prefix}/REDIS_HOST"
  type  = "String"
  value = var.redis_endpoint
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "${local.prefix}/REDIS_PASSWORD"
  type  = "SecureString"
  value = var.redis_password
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name  = "${local.prefix}/COGNITO_USER_POOL_ID"
  type  = "String"
  value = var.cognito_user_pool_id
}

resource "aws_ssm_parameter" "cognito_client_id" {
  name  = "${local.prefix}/COGNITO_CLIENT_ID"
  type  = "String"
  value = var.cognito_client_id
}

resource "aws_ssm_parameter" "sqs_url" {
  name  = "${local.prefix}/SQS_URL"
  type  = "String"
  value = var.sqs_url
}

resource "aws_ssm_parameter" "grafana_admin_password" {
  name  = "${local.prefix}/GRAFANA_ADMIN_PASSWORD"
  type  = "SecureString"
  value = var.grafana_admin_password
}

resource "aws_ssm_parameter" "alertmanager_slack_webhook" {
  name  = "${local.prefix}/ALERTMANAGER_SLACK_WEBHOOK"
  type  = "SecureString"
  value = var.alertmanager_slack_webhook
}
