variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "keda_operator_role_arn" { type = string }

variable "version" {
  type    = string
  default = "2.15.2"
}

variable "namespace" {
  type    = string
  default = "keda"
}
