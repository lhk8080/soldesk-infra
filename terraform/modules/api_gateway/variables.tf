variable "env" { type = string }
variable "aws_region" { type = string }

variable "vpc_id" { type = string }

variable "private_subnet_ids" {
  description = "VPC Link가 사용할 private subnet (Internal ALB와 같은 서브넷)"
  type        = list(string)
}

variable "cognito_user_pool_id" {
  description = "JWT Authorizer가 검증할 Cognito User Pool ID"
  type        = string
}

variable "cognito_user_pool_client_id" {
  description = "JWT audience 검증용 Cognito App Client ID"
  type        = string
}

variable "cluster_name" {
  description = "ALB 태그 lookup용 EKS 클러스터 이름 (elbv2.k8s.aws/cluster)"
  type        = string
}

variable "ingress_stack_tag" {
  description = "ALB Ingress 식별 태그 (ingress.k8s.aws/stack = <ns>/<ingress-name>)"
  type        = string
  default     = "ticketing/ticketing-ingress"
}
