variable "env" {
  type = string
}
variable "app_name" {
  type    = string
  default = "ticketing"
}
variable "aws_region" {
  type = string
}
variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (eks 모듈 output)"
  type        = string
}
variable "oidc_issuer" {
  description = "EKS OIDC issuer (https:// 제거된 host/path)"
  type        = string
}
variable "ssm_parameter_prefix" {
  description = "ESO에 권한을 줄 SSM 경로 prefix (예: /ticketing/prod)"
  type        = string
}
variable "eso_namespace" {
  description = "ESO 컨트롤러가 설치되는 네임스페이스"
  type        = string
  default     = "external-secrets"
}
variable "eso_service_account" {
  description = "ticketing의 ExternalSecret이 사용할 SA 이름. SecretStore.spec.provider.aws.auth.jwt.serviceAccountRef로 참조됨"
  type        = string
  default     = "ticketing-eso-sa"
}
variable "ticketing_namespace" {
  description = "ESO SA가 거주하는 네임스페이스 (보통 앱 ns와 동일)"
  type        = string
  default     = "ticketing"
}

variable "extra_service_account_subjects" {
  description = "ESO IRSA role 을 AssumeRoleWithWebIdentity 로 사용할 수 있는 추가 SA 목록. 형식: system:serviceaccount:<ns>:<sa-name>"
  type        = list(string)
  default     = []
}
