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
