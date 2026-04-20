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
