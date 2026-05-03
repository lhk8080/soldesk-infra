variable "project" {
  description = "Project name"
  type        = string
  default     = "sol-ticketing"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "domain_name" {
  description = "Route53 호스티드존 루트 도메인 (예: hk99.shop)"
  type        = string
}
