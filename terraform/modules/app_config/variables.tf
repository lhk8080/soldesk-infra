variable "namespace" {
  description = "Secret/ConfigMap이 생성될 네임스페이스"
  type        = string
  default     = "ticketing"
}

variable "secret_name" {
  description = "생성할 Secret 이름 (차트의 secretName과 일치)"
  type        = string
  default     = "ticketing-secrets"
}

variable "configmap_name" {
  description = "생성할 ConfigMap 이름 (차트의 configMapName과 일치)"
  type        = string
  default     = "ticketing-config"
}

variable "aws_region" {
  type = string
}

# ── RDS ────────────────────────────────────────────────
variable "db_writer_host" { type = string }
variable "db_reader_host" { type = string }
variable "db_port" {
  type    = number
  default = 3306
}
variable "db_name" {
  type    = string
  default = "ticketing"
}
variable "db_user" {
  type    = string
  default = "root"
}
variable "db_password" {
  type      = string
  sensitive = true
}

# ── ElastiCache (Redis) ────────────────────────────────
variable "redis_host" { type = string }
variable "redis_port" {
  type    = number
  default = 6379
}

# ── SQS ────────────────────────────────────────────────
variable "sqs_queue_url" { type = string }
variable "sqs_queue_interactive_url" { type = string }

# ── Cognito ────────────────────────────────────────────
variable "cognito_user_pool_id" { type = string }
variable "cognito_app_client_id" { type = string }
