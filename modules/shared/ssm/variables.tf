variable "env" { type = string }

variable "app_name" {
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

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "db_writer_endpoint" { type = string }
variable "db_reader_endpoint" { type = string }
variable "redis_endpoint"     { type = string }
variable "cognito_user_pool_id" { type = string }
variable "cognito_client_id"    { type = string }
variable "sqs_url"              { type = string }

variable "grafana_admin_password" {
  type      = string
  sensitive = true
  default   = "soldesk1"
}

variable "alertmanager_slack_webhook" {
  type      = string
  sensitive = true
  default   = "https://hooks.slack.com/services/dummy"
}

variable "argocd_slack_webhook" {
  type      = string
  sensitive = true
  default   = "https://hooks.slack.com/services/dummy"
}
