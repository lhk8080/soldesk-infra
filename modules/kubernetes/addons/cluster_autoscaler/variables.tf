variable "cluster_name" { type = string }
variable "aws_region" { type = string }

variable "role_arn" {
  type        = string
  description = "Cluster Autoscaler ServiceAccount 에 붙일 IRSA role ARN"
}

variable "chart_version" {
  type    = string
  default = "9.43.2"
}

variable "namespace" {
  type    = string
  default = "kube-system"
}
