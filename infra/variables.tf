variable "env"        { type = string }
variable "aws_region" { type = string }
variable "aws_account" {
  type        = string
  description = "12자리 AWS 계정 ID (S3 버킷 이름 suffix에 사용)"
}

variable "cluster_name"          { type = string }
variable "cognito_domain_prefix" { type = string }
variable "github_repo" {
  type        = string
  description = "GitHub Actions OIDC 허용 레포 (예: my-org/my-repo)"
}

# 두 번째 apply 때 실제 값으로 채워줌
variable "cloudfront_domain" {
  type    = string
  default = ""
}
variable "alb_listener_arn" {
  type    = string
  default = ""
}

# Slack webhook (ArgoCD notifications) — tfvars 에 반드시 박아야 함 (default 없음)
variable "argocd_slack_webhook" {
  type      = string
  sensitive = true
}

# EKS 노드 그룹
variable "app_node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
variable "app_node_desired_size" {
  type    = number
  default = 2
}
variable "app_node_min_size" {
  type    = number
  default = 1
}
variable "app_node_max_size" {
  type    = number
  default = 4
}

# RDS
variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}
variable "rds_allocated_storage" {
  type    = number
  default = 20
}
variable "rds_max_allocated_storage" {
  type    = number
  default = 100
}

# ElastiCache
variable "elasticache_node_type" {
  type    = string
  default = "cache.t3.micro"
}
