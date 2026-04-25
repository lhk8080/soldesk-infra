resource "random_password" "db" {
  length  = 20
  special = false
}

resource "random_password" "redis" {
  length  = 20
  special = false
}

# ── Network ──────────────────────────────────────────────────────────────────

module "network" {
  source           = "../modules/network"
  env              = var.env
  aws_region       = var.aws_region
  eks_cluster_name = var.cluster_name
}

# ── Compute ───────────────────────────────────────────────────────────────────

module "compute" {
  source = "../modules/compute"

  env              = var.env
  aws_region       = var.aws_region
  cluster_name     = var.cluster_name
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.public_subnet_ids
  security_group_id = module.network.eks_sg_id
  pod_subnet_ids   = module.network.pod_subnet_ids
  pod_subnet_azs   = module.network.pod_subnet_azs

  app_node_instance_types = var.app_node_instance_types
  app_node_desired_size   = var.app_node_desired_size
  app_node_min_size       = var.app_node_min_size
  app_node_max_size       = var.app_node_max_size

  sqs_queue_arns             = [module.sqs.reservation_queue_arn]
  assets_bucket_arn          = module.s3.assets_bucket_arn
  enable_db_backup_to_assets = true
}

# ── Data ──────────────────────────────────────────────────────────────────────

module "rds" {
  source = "../modules/data/rds"

  env               = var.env
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.rds_sg_id
  db_password       = random_password.db.result

  writer_instance_class = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
}

module "elasticache" {
  source = "../modules/data/elasticache"

  env               = var.env
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.redis_sg_id
  node_type         = var.elasticache_node_type
}

# ── Messaging ─────────────────────────────────────────────────────────────────

module "sqs" {
  source = "../modules/messaging/sqs"
  env    = var.env
}

# ── Identity ──────────────────────────────────────────────────────────────────

module "lambda" {
  source = "../modules/identity/lambda"
}

module "cognito" {
  source = "../modules/identity/cognito"

  env                              = var.env
  cognito_domain_prefix            = var.cognito_domain_prefix
  cloudfront_domain                = var.cloudfront_domain
  pre_sign_up_lambda_arn           = module.lambda.auto_confirm_arn
  pre_sign_up_lambda_function_name = module.lambda.auto_confirm_function_name
}

# ── Shared ────────────────────────────────────────────────────────────────────

module "ecr" {
  source = "../modules/shared/ecr"
  env    = var.env
}

module "s3" {
  source      = "../modules/shared/s3"
  env         = var.env
  aws_account = var.aws_account
}

module "cicd" {
  source = "../modules/shared/cicd"

  env             = var.env
  aws_region      = var.aws_region
  github_repo     = var.github_repo
  cluster_name    = var.cluster_name
  s3_frontend_arn = module.s3.frontend_bucket_arn
}

module "ssm" {
  source = "../modules/shared/ssm"

  env            = var.env
  db_password    = random_password.db.result
  redis_password = random_password.redis.result

  db_host              = module.rds.writer_endpoint
  redis_host           = module.elasticache.redis_endpoint
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.user_pool_client_id
  sqs_url              = module.sqs.reservation_queue_url
}

# ── Edge ──────────────────────────────────────────────────────────────────────

module "waf" {
  source = "../modules/edge/waf"
  providers = { aws.us_east_1 = aws.us_east_1 }
  env = var.env
}

module "cloudfront" {
  source = "../modules/edge/cloudfront"

  env                       = var.env
  frontend_bucket_id        = module.s3.frontend_bucket_id
  frontend_bucket_arn       = module.s3.frontend_bucket_arn
  frontend_domain           = module.s3.frontend_bucket_regional_domain
  waf_acl_arn               = module.waf.waf_acl_arn
  api_gateway_endpoint_host = var.alb_listener_arn != "" ? module.api_gateway.api_endpoint_host : ""
}

module "api_gateway" {
  source = "../modules/edge/api-gateway"

  env                        = var.env
  aws_region                 = var.aws_region
  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  cognito_user_pool_id       = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  alb_listener_arn           = var.alb_listener_arn
}
