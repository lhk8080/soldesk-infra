variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "cluster_name" {
  type        = string
  description = "infra에서 생성한 EKS 클러스터 이름"
}

variable "argocd_version" {
  type    = string
  default = "7.8.26"
}

variable "keda_version" {
  type    = string
  default = "2.15.2"
}

variable "alb_controller_version" {
  type    = string
  default = "1.8.1"
}

variable "domain_name" {
  type        = string
  description = "infra 모듈에서 출력된 루트 도메인 (argocd/grafana 서브도메인 베이스)"
}

variable "waf_regional_acl_arn" {
  type        = string
  description = "infra 모듈에서 생성한 REGIONAL WAFv2 ACL ARN"
}
