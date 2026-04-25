variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "role_arn" { type = string }

variable "version" {
  type    = string
  default = "1.8.1"
}

variable "namespace" {
  type    = string
  default = "kube-system"
}
