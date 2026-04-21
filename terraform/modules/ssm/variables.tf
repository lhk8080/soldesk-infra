variable "env" {
  type = string
}
variable "app_name" {
  type    = string
  default = "ticketing"
}
variable "aws_region" {
  type = string
}

# ── DB ────────────────────────────────────────────────
variable "db_writer_host" { type = string }
variable "db_reader_host" { type = string }
variable "db_user" {
  type    = string
  default = "root"
}
variable "db_password" {
  type      = string
  sensitive = true
}

# ── Redis ─────────────────────────────────────────────
variable "redis_host" { type = string }

# ── SQS ───────────────────────────────────────────────
variable "sqs_queue_url" { type = string }
variable "sqs_queue_interactive_url" { type = string }

# ── Cognito ───────────────────────────────────────────
variable "cognito_user_pool_id" { type = string }
variable "cognito_app_client_id" { type = string }

# ── Alertmanager ──────────────────────────────────────
# Slack incoming webhook URL. 미설정 시 빈 문자열 저장 → Alertmanager 는 기동되지만 전송 실패.
# 운영 시작 전 aws ssm put-parameter --name /<app>/<env>/alertmanager/slack_webhook --value <url> --overwrite 로 덮어쓰면 됨.
variable "alertmanager_slack_webhook" {
  type      = string
  default   = ""
  sensitive = true
}
