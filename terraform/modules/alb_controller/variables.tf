variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "role_arn" {
  description = "IRSA role ARN for aws-load-balancer-controller SA"
  type        = string
}

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart 버전"
  type        = string
  default     = "1.8.1"
}
