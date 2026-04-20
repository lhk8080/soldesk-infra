variable "env" {
  description = "배포 환경 (dev, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "app_name" {
  description = "애플리케이션 이름"
  type        = string
  default     = "ticketing"
}

# RDS 비번은 modules/rds 가 random_password로 생성하고 SSM에 저장한다 (ESO가 K8s Secret으로 주입).
# tfvars/환경변수에서 받지 않는다.

variable "github_repo" {
  description = "GitHub 리포지토리 (owner/repo)"
  type        = string
  default     = "your-org/ticketing"
}

variable "eks_cluster_name" {
  description = "EKS 클러스터 이름. 서브넷 태그 kubernetes.io/cluster/<이 값> 과 동일해야 합니다. 변경 시 클러스터가 재생성될 수 있습니다."
  type        = string
  default     = "ticketing-eks"
}

# cognito <-> cloudfront <-> api_gateway 순환 참조를 끊기 위해 root-level 변수로 관리.
# 첫 apply: 빈 문자열 → cognito는 http://localhost placeholder URL 사용
# setup-all.sh가 첫 apply 후 cloudfront_domain을 tfvars에 박고 재apply하면
# 실제 CloudFront 도메인으로 callback/logout URL이 갱신된다.
variable "frontend_callback_domain" {
  description = "Cognito 콜백/로그아웃 URL 생성용 프론트엔드 도메인 (CloudFront). setup-all.sh가 자동 주입."
  type        = string
  default     = ""
}

# ArgoCD Application(루트 App) 등록은 Terraform 밖에서 kubectl apply 로 처리.
# soldesk-k8s/argocd/application-prod.yaml 을 참고.

variable "cognito_domain_prefix" {
  description = "Cognito 호스티드 UI 도메인 접두사 (전역 유일)"
  type        = string
  default     = "ticketing-auth-734772"
}
