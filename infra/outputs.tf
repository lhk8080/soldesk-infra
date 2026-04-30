# 두 번째 apply 때 values.tfvars에 채워넣을 값들
output "cloudfront_domain"    { value = module.cloudfront.cloudfront_domain }
output "api_endpoint_host"    { value = module.api_gateway.api_endpoint_host }

output "cluster_name"         { value = module.compute.cluster_name }
output "cluster_endpoint"     { value = module.compute.cluster_endpoint }

output "cognito_user_pool_id" { value = module.cognito.user_pool_id }
output "cognito_client_id"    { value = module.cognito.user_pool_client_id }
output "cognito_domain"       { value = module.cognito.cognito_domain }

output "ecr_ticketing_was_url" { value = module.ecr.ticketing_was_url }
output "ecr_worker_svc_url"    { value = module.ecr.worker_svc_url }

output "frontend_bucket_id"   { value = module.s3.frontend_bucket_id }
output "sqs_reservation_url"  { value = module.sqs.reservation_queue_url }
output "sqs_reservation_url_dev" { value = module.sqs_dev.reservation_queue_url }

output "github_actions_role_arn" { value = module.cicd.github_actions_role_arn }

output "assets_bucket_id"      { value = module.s3.assets_bucket_id }
output "sqs_access_role_arn"   { value = module.compute.sqs_access_role_arn }
output "db_backup_role_arn"    { value = module.compute.db_backup_role_arn }
output "eso_role_arn"          { value = module.compute.eso_role_arn }

output "route53_name_servers" {
  description = "가비아 네임서버 설정에 입력할 NS 4개"
  value       = module.route53.name_servers
}
output "acm_alb_certificate_arn"        { value = module.acm_alb.certificate_arn }
output "acm_cloudfront_certificate_arn" { value = module.acm_cloudfront.certificate_arn }
