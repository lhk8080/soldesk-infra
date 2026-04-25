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
