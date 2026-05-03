output "s3_bucket_name" {
  description = "Terraform state S3 bucket name"
  value       = aws_s3_bucket.tfstate.id
}

output "dynamodb_table_name" {
  description = "Terraform state lock DynamoDB table name"
  value       = aws_dynamodb_table.tflock.name
}

output "github_actions_role_arn" {
  description = "IAM Role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "가비아에 등록할 Route53 네임서버"
  value       = aws_route53_zone.main.name_servers
}
