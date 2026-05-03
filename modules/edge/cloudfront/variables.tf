variable "env" { type = string }
variable "frontend_bucket_id" { type = string }
variable "frontend_bucket_arn" { type = string }
variable "frontend_domain" { type = string }
variable "waf_acl_arn" { type = string }

variable "aliases" {
  type        = list(string)
  description = "CloudFront 에 연결할 도메인 (예: [\"hk99.shop\", \"www.hk99.shop\"]). 비어있으면 default cert 사용."
  default     = []
}

variable "acm_certificate_arn" {
  type        = string
  description = "us-east-1 ACM cert ARN. aliases 가 비어있지 않으면 필수."
  default     = ""
}

variable "api_gateway_endpoint_host" {
  type        = string
  description = "API Gateway invoke 도메인 (예: abc123.execute-api.ap-northeast-2.amazonaws.com). 빈 문자열이면 API origin 생성 안 함."
  default     = ""
}
