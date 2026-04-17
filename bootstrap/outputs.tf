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
