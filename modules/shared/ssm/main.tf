locals {
  prefix = "/${var.app_name}/${var.env}"
}

resource "aws_ssm_parameter" "db_password" {
  name  = "${local.prefix}/secret/db-password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "redis_password" {
  name  = "${local.prefix}/secret/redis-password"
  type  = "SecureString"
  value = var.redis_password
}

resource "aws_ssm_parameter" "db_host" {
  name  = "${local.prefix}/config/db-host"
  type  = "String"
  value = var.db_host
}

resource "aws_ssm_parameter" "redis_host" {
  name  = "${local.prefix}/config/redis-host"
  type  = "String"
  value = var.redis_host
}

resource "aws_ssm_parameter" "cognito_user_pool_id" {
  name  = "${local.prefix}/config/cognito-user-pool-id"
  type  = "String"
  value = var.cognito_user_pool_id
}

resource "aws_ssm_parameter" "cognito_client_id" {
  name  = "${local.prefix}/config/cognito-client-id"
  type  = "String"
  value = var.cognito_client_id
}

resource "aws_ssm_parameter" "sqs_url" {
  name  = "${local.prefix}/config/sqs-url"
  type  = "String"
  value = var.sqs_url
}
