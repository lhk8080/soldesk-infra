output "role_arn" {
  description = "ESO가 사용할 IRSA role ARN. ticketing-eso-sa의 eks.amazonaws.com/role-arn annotation으로 주입."
  value       = aws_iam_role.eso.arn
}

output "service_account" {
  description = "ESO SecretStore.spec.provider.aws.auth.jwt.serviceAccountRef.name 값"
  value       = var.eso_service_account
}

output "namespace" {
  description = "ESO 컨트롤러가 설치되는 네임스페이스"
  value       = var.eso_namespace
}
