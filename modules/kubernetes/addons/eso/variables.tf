variable "namespace" {
  type    = string
  default = "external-secrets"
}

variable "chart_version" {
  type    = string
  default = "0.10.0"
}

variable "role_arn" {
  type        = string
  description = "ESO ServiceAccount에 붙일 IRSA role ARN"
}
