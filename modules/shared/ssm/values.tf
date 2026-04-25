variable "env" { type = string }

variable "app_name" {
  type    = string
  default = "ticketing"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "db_host"              { type = string }
variable "redis_host"           { type = string }
variable "cognito_user_pool_id" { type = string }
variable "cognito_client_id"    { type = string }
variable "sqs_url"              { type = string }
