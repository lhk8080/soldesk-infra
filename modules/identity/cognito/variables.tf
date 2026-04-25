variable "env" { type = string }

variable "app_name" {
  type    = string
  default = "ticketing"
}

variable "cognito_domain_prefix" { type = string }

variable "cloudfront_domain" {
  type        = string
  description = "CloudFront 배포 도메인 (콜백/로그아웃 URL 생성용). 빈 문자열이면 localhost placeholder 사용."
  default     = ""
}

variable "pre_sign_up_lambda_arn" {
  type        = string
  description = "Cognito pre_sign_up 트리거 Lambda ARN (lambda 모듈 output)"
}

variable "pre_sign_up_lambda_function_name" {
  type        = string
  description = "Lambda 함수명 — aws_lambda_permission 생성에 필요"
}
