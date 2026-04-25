variable "env" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }

variable "private_subnet_ids" {
  type        = list(string)
  description = "VPC Link가 사용할 private subnet (Internal ALB와 같은 서브넷)"
}

variable "cognito_user_pool_id" {
  type        = string
  description = "JWT Authorizer가 검증할 Cognito User Pool ID"
}

variable "cognito_user_pool_client_id" {
  type        = string
  description = "JWT audience 검증용 Cognito App Client ID"
}

variable "alb_listener_arn" {
  type        = string
  description = "Internal ALB HTTP listener ARN. 빈 문자열이면 Integration/Route 생성 안 함 (첫 apply)"
  default     = ""
}
