variable "namespace" {
  description = "ArgoCD가 설치될 네임스페이스"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "argo-cd Helm chart 버전 (https://github.com/argoproj/argo-helm/releases)"
  type        = string
  default     = "7.7.10"
}

variable "values" {
  description = "argo-cd chart values 오버라이드 (YAML 문자열)"
  type        = string
  default     = ""
}
