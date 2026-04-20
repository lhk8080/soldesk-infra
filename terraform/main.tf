terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  required_version = ">= 1.5.0"
}

provider "aws" {
  region = var.aws_region
}

# CloudFront용 WAF는 반드시 us-east-1에 생성해야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Helm provider: EKS 클러스터에 차트 설치용
# exec plugin으로 매 apply마다 새 토큰 발급 (kubeconfig 의존성 제거)
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}

# Kubernetes provider: ArgoCD Application CR 등 k8s 오브젝트 선언적 관리용
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

module "network" {
  source           = "./modules/network"
  env              = var.env
  aws_region       = var.aws_region
  eks_cluster_name = var.eks_cluster_name
}

module "cognito" {
  source                = "./modules/cognito"
  env                   = var.env
  app_name              = var.app_name
  cognito_domain_prefix = var.cognito_domain_prefix
  # root-level var 경유로 순환 참조 차단 (module.cloudfront → cognito 직접 참조 금지)
  cloudfront_domain = var.frontend_callback_domain
}

module "s3" {
  source      = "./modules/s3"
  env         = var.env
  aws_account = data.aws_caller_identity.current.account_id
}

module "waf" {
  source = "./modules/waf"
  env    = var.env

  providers = {
    aws = aws.us_east_1
  }
}

module "cloudfront" {
  source                    = "./modules/cloudfront"
  env                       = var.env
  frontend_bucket_id        = module.s3.frontend_bucket_id
  frontend_bucket_arn       = module.s3.frontend_bucket_arn
  frontend_domain           = module.s3.frontend_bucket_regional_domain
  waf_acl_arn               = module.waf.waf_acl_arn
  api_gateway_endpoint_host = module.api_gateway.api_endpoint_host

  # destroy 시 CloudFront가 WAF보다 먼저 삭제되도록 보장
  # (WAF가 먼저 삭제되면 CloudFront destroy가 실패)
  depends_on = [module.waf, module.api_gateway]
}

# ── API Gateway (HTTP API + Cognito JWT Authorizer + VPC Link) ────
# CloudFront의 origin으로 사용. Internal ALB와는 VPC Link로 연결
# 첫 apply 시 alb_listener_arn=""이면 API GW 본체만 만들고
# Integration/Route는 두 번째 apply (setup-all.sh가 listener ARN 박은 후)에서 생성
module "api_gateway" {
  source     = "./modules/api_gateway"
  env        = var.env
  aws_region = var.aws_region

  vpc_id                      = module.network.vpc_id
  private_subnet_ids          = module.network.private_subnet_ids
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id
  cluster_name                = var.eks_cluster_name

  # ArgoCD가 ticketing-ingress를 동기화한 뒤에야 ALB Controller가 ALB를 생성함.
  # 그 전에 api_gateway가 Integration 만들면 ALB lookup 실패.
  depends_on = [module.network, module.cognito, module.argocd]
}

module "sqs" {
  source = "./modules/sqs"
  env    = var.env
}

module "elasticache" {
  source            = "./modules/elasticache"
  env               = var.env
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.redis_sg_id

  # destroy 시 ElastiCache가 네트워크(SG/서브넷)보다 먼저 삭제되도록 보장
  depends_on = [module.network]
}

module "rds" {
  source            = "./modules/rds"
  env               = var.env
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.rds_sg_id

  # destroy 시 RDS가 네트워크(SG/서브넷)보다 먼저 삭제되도록 보장
  depends_on = [module.network]
}

# ── EKS 삭제 후 VPC 고아 리소스 정리 ──────────────────────────────
# Destroy 순서: module.eks → post_eks_vpc_cleanup → module.network
# EKS 삭제 후 K8s 컨트롤러가 남긴 보안그룹·ENI를 제거하여 VPC 삭제 hang 영구 방지
resource "null_resource" "post_eks_vpc_cleanup" {
  triggers = {
    vpc_id = module.network.vpc_id
    region = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "=== Post-EKS VPC cleanup: K8s 고아 리소스 제거 ==="
      VPC_ID="${self.triggers.vpc_id}"
      REGION="${self.triggers.region}"
      [ -z "$VPC_ID" ] && exit 0

      # K8s/EKS가 생성한 보안 그룹 (k8s-*, eks-cluster-sg-*)
      K8S_SGS=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=k8s-*,eks-cluster-sg-*" \
        --query 'SecurityGroups[*].GroupId' --output text 2>/dev/null)

      if [ -n "$K8S_SGS" ] && [ "$K8S_SGS" != "None" ]; then
        echo "고아 보안 그룹 발견: $K8S_SGS"
        # 1단계: 상호 참조 규칙 제거
        for SG_ID in $K8S_SGS; do
          INGRESS=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
            --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null)
          if [ "$INGRESS" != "[]" ] && [ -n "$INGRESS" ]; then
            aws ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$INGRESS" --region "$REGION" 2>/dev/null || true
          fi
          EGRESS=$(aws ec2 describe-security-groups --group-ids "$SG_ID" --region "$REGION" \
            --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>/dev/null)
          if [ "$EGRESS" != "[]" ] && [ -n "$EGRESS" ]; then
            aws ec2 revoke-security-group-egress --group-id "$SG_ID" --ip-permissions "$EGRESS" --region "$REGION" 2>/dev/null || true
          fi
        done
        # 2단계: 보안 그룹 삭제
        for SG_ID in $K8S_SGS; do
          echo "  삭제: $SG_ID"
          aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION" 2>/dev/null || true
        done
      else
        echo "정리할 고아 보안 그룹 없음"
      fi

      # 고아 ENI 분리 및 삭제
      for ENI_ID in $(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[?Attachment.DeviceIndex!=\`0\`].NetworkInterfaceId" \
        --output text 2>/dev/null); do
        ATTACH_ID=$(aws ec2 describe-network-interfaces --region "$REGION" \
          --network-interface-ids "$ENI_ID" \
          --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text 2>/dev/null)
        if [ "$ATTACH_ID" != "None" ] && [ -n "$ATTACH_ID" ]; then
          aws ec2 detach-network-interface --attachment-id "$ATTACH_ID" --force --region "$REGION" 2>/dev/null || true
        fi
      done
      sleep 10
      for ENI_ID in $(aws ec2 describe-network-interfaces --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
        --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null); do
        echo "  ENI 삭제: $ENI_ID"
        aws ec2 delete-network-interface --network-interface-id "$ENI_ID" --region "$REGION" 2>/dev/null || true
      done

      echo "=== Post-EKS VPC cleanup 완료 ==="
    EOT
  }
}

module "eks" {
  source            = "./modules/eks"
  env               = var.env
  aws_region        = var.aws_region
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.network.eks_sg_id
  cluster_name      = var.eks_cluster_name
  sqs_queue_arns = [
    module.sqs.reservation_queue_arn,
    module.sqs.reservation_dlq_arn,
    module.sqs.reservation_ui_queue_arn,
    module.sqs.reservation_ui_dlq_arn,
  ]

  # destroy 순서: module.eks → post_eks_vpc_cleanup → module.network
  depends_on = [module.network, null_resource.post_eks_vpc_cleanup]
}

# AWS Load Balancer Controller: ticketing-ingress(alb)가 실제 ALB로 프로비저닝되려면 필요.
# eks 모듈이 IRSA role을 이미 만들어 두었으므로 여기서는 설치 + SA 바인딩만 수행.
module "alb_controller" {
  source = "./modules/alb_controller"

  cluster_name = module.eks.cluster_name
  aws_region   = var.aws_region
  vpc_id       = module.network.vpc_id
  role_arn     = module.eks.alb_controller_role_arn

  depends_on = [module.eks]
}

# KEDA: ticketing 차트의 ScaledObject/TriggerAuthentication이 의존하는 CRD 제공.
# ArgoCD 루트 App이 ticketing을 동기화하기 전에 CRD가 있어야 하므로 argocd보다 먼저 설치.
module "keda" {
  source = "./modules/keda"

  operator_role_arn = module.eks.keda_operator_role_arn

  depends_on = [module.eks]
}

# 앱 런타임 시크릿/엔드포인트는 SSM Parameter Store에 저장하고
# ESO(External Secrets Operator)가 ticketing-secrets K8s Secret으로 머티리얼라이즈.
# (이전: module.app_config 가 kubernetes_secret 으로 직접 생성 → 폐기)
module "ssm" {
  source = "./modules/ssm"

  env        = var.env
  app_name   = var.app_name
  aws_region = var.aws_region

  db_writer_host = module.rds.writer_endpoint
  db_reader_host = module.rds.reader_endpoint
  db_password    = module.rds.db_password

  redis_host = module.elasticache.redis_endpoint

  sqs_queue_url             = module.sqs.reservation_queue_url
  sqs_queue_interactive_url = module.sqs.reservation_ui_queue_url

  cognito_user_pool_id  = module.cognito.user_pool_id
  cognito_app_client_id = module.cognito.user_pool_client_id
}

# ESO IRSA role. ESO 차트는 ArgoCD App-of-Apps(soldesk-k8s/argocd/platform/external-secrets.yaml)
# 가 설치하므로 여기서는 IAM만 만든다.
module "external_secrets" {
  source = "./modules/external_secrets"

  env                  = var.env
  app_name             = var.app_name
  aws_region           = var.aws_region
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_issuer          = module.eks.oidc_issuer
  ssm_parameter_prefix = module.ssm.parameter_prefix

  # monitoring 차트의 ESO SA 도 동일 role 을 AssumeRole 할 수 있게 허용.
  # IAM 정책 Resource(/ticketing/prod/*) 안에 grafana/*, alertmanager/* 도 들어가므로 권한 범위는 그대로.
  extra_service_account_subjects = [
    "system:serviceaccount:monitoring:monitoring-eso-sa",
  ]

  depends_on = [module.eks]
}

# ArgoCD: GitOps 진입점. Helm 설치만 담당.
# Application(루트 App) 등록은 Terraform 밖에서 kubectl apply 로 수행 (apply.sh).
# → kubernetes_manifest 의 plan-time CRD 검증 의존성을 회피.
module "argocd" {
  source = "./modules/argocd"

  depends_on = [module.eks, module.keda]
}

module "cicd" {
  source          = "./modules/cicd"
  env             = var.env
  aws_region      = var.aws_region
  github_repo     = var.github_repo
  cluster_name    = module.eks.cluster_name
  s3_frontend_arn = module.s3.frontend_bucket_arn
}

data "aws_caller_identity" "current" {}

# EKS 노드가 실제 사용하는 클러스터 SG → RDS/Redis 접근 허용
# (EKS는 vpc_config.security_group_ids 외에 자체 클러스터 SG를 자동 생성하여 노드에 할당)
resource "aws_security_group_rule" "rds_from_eks_cluster_sg" {
  type                     = "ingress"
  description              = "MySQL from EKS cluster SG"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.network.rds_sg_id
  source_security_group_id = module.eks.cluster_security_group_id
}

resource "aws_security_group_rule" "redis_from_eks_cluster_sg" {
  type                     = "ingress"
  description              = "Redis from EKS cluster SG"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = module.network.redis_sg_id
  source_security_group_id = module.eks.cluster_security_group_id
}

# EKS 노드 → SQS 접근 허용 (reserv-svc, worker-svc 에서 사용)
resource "aws_iam_role_policy" "eks_node_sqs" {
  name = "ticketing-eks-node-sqs"
  role = module.eks.node_role_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
      ]
      Resource = [
        module.sqs.reservation_queue_arn,
        module.sqs.reservation_dlq_arn,
        module.sqs.reservation_ui_queue_arn,
        module.sqs.reservation_ui_dlq_arn,
      ]
    }]
  })
}

