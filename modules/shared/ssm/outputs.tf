output "db_password_arn"           { value = aws_ssm_parameter.db_password.arn }
output "redis_password_arn"        { value = aws_ssm_parameter.redis_password.arn }
output "db_host_arn"               { value = aws_ssm_parameter.db_host.arn }
output "redis_host_arn"            { value = aws_ssm_parameter.redis_host.arn }
output "cognito_user_pool_id_arn"  { value = aws_ssm_parameter.cognito_user_pool_id.arn }
output "cognito_client_id_arn"     { value = aws_ssm_parameter.cognito_client_id.arn }
output "sqs_url_arn"               { value = aws_ssm_parameter.sqs_url.arn }

output "parameter_prefix" { value = "/${var.app_name}/${var.env}" }
