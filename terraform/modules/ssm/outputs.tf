output "parameter_prefix" {
  description = "SSM 파라미터 경로 prefix (예: /ticketing/prod). ESO ExternalSecret과 IAM 정책이 이 값에 의존."
  value       = local.prefix
}

output "parameter_arns" {
  description = "생성된 모든 SSM 파라미터의 ARN 리스트 (감사용)"
  value       = [for p in aws_ssm_parameter.this : p.arn]
}
