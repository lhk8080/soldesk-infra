variable "namespace" {
  description = "KEDA가 설치될 네임스페이스"
  type        = string
  default     = "keda"
}

variable "chart_version" {
  description = "keda Helm chart 버전 (https://github.com/kedacore/charts/releases)"
  type        = string
  default     = "2.15.2"
}

variable "operator_role_arn" {
  description = "keda-operator SA에 IRSA로 바인딩할 IAM Role ARN (SQS 호출 권한 보유)"
  type        = string
}
