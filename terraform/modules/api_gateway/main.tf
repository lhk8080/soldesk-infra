# ── API Gateway HTTP API ───────────────────────────────────────────
# 흐름: CloudFront → API Gateway (Cognito JWT Authorizer) → VPC Link → Internal ALB → EKS
#
# 핵심 설계:
#   1. HTTP API + JWT Authorizer = Cognito 토큰 자동 검증, 백엔드 코드 0
#   2. VPC Link v2 = Internal ALB로 직접 연결 (NLB 불필요)
#   3. Integration request_parameters = 검증된 email을 x-user-email 헤더로 매핑
#      → 백엔드는 기존 request.headers.get("x-user-email") 코드 그대로 사용
#      → 헤더 위조 차단 (API GW가 인증된 토큰의 claim만 헤더로 주입)
#   4. ALB는 ALB Ingress Controller가 k8s Ingress를 보고 생성 → 태그로 lookup
#      (과거: setup-all.sh가 listener ARN을 tfvars에 박는 2-apply 구조 → 제거됨)

resource "aws_apigatewayv2_api" "main" {
  name          = "ticketing-http-api"
  protocol_type = "HTTP"
  description   = "Ticketing API Gateway — Cognito JWT 인증 + Internal ALB 프록시"

  cors_configuration {
    allow_origins  = ["*"]
    allow_methods  = ["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"]
    allow_headers  = ["Authorization", "Content-Type", "x-amz-date", "x-amz-security-token"]
    expose_headers = ["*"]
    max_age        = 300
  }

  tags = { Name = "ticketing-http-api", Environment = var.env }
}

# ── Cognito JWT Authorizer ─────────────────────────────────────────
# Authorization 헤더의 JWT 토큰을 자동 검증
# - issuer가 우리 Cognito User Pool인지
# - audience(aud)가 우리 App Client ID인지
# - 서명이 Cognito 공개키와 일치하는지
# 검증 통과 시 $context.authorizer.claims.* 로 토큰 내용에 접근 가능
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito-jwt-authorizer"

  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# ── VPC Link v2 ────────────────────────────────────────────────────
# API Gateway가 private VPC 안의 Internal ALB로 트래픽을 전달하기 위한 통로
# v2는 ALB·NLB·CloudMap을 직접 지원 (v1과 달리 NLB 강제 X)
resource "aws_security_group" "vpc_link" {
  name        = "ticketing-apigw-vpclink-sg"
  description = "API Gateway VPC Link to Internal ALB"
  vpc_id      = var.vpc_id

  egress {
    description = "To Internal ALB (HTTP)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  tags = { Name = "ticketing-apigw-vpclink-sg", Environment = var.env }
}

resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "ticketing-vpc-link"
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.private_subnet_ids

  tags = { Name = "ticketing-vpc-link", Environment = var.env }
}

# ── ALB Ingress가 만든 ALB lookup (태그 기반) ──────────────────────
# ALB Ingress Controller는 아래 태그를 자동으로 붙인다:
#   elbv2.k8s.aws/cluster = <cluster-name>
#   ingress.k8s.aws/stack = <namespace>/<ingress-name>
# Ingress는 ArgoCD 동기화가 끝난 뒤에 생성되므로 이 data는 null_resource.wait_for_alb
# 이후에만 resolve된다 (depends_on).
data "aws_lb" "ingress" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "ingress.k8s.aws/stack" = var.ingress_stack_tag
  }

  depends_on = [null_resource.wait_for_alb]
}

data "aws_lb_listener" "ingress" {
  load_balancer_arn = data.aws_lb.ingress.arn
  port              = 80
}

# ── ALB 등장 대기 ──────────────────────────────────────────────────
# ArgoCD가 ticketing-ingress를 동기화하면 ALB Controller가 ALB를 프로비저닝한다.
# 프로비저닝 완료까지 aws cli로 폴링.
resource "null_resource" "wait_for_alb" {
  triggers = {
    cluster = var.cluster_name
    stack   = var.ingress_stack_tag
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "=== ALB 등장 대기 (cluster=${var.cluster_name}, stack=${var.ingress_stack_tag}) ==="
      for i in $(seq 1 60); do
        ARN=$(aws elbv2 describe-load-balancers --region ${var.aws_region} \
          --query "LoadBalancers[?contains(LoadBalancerName, \`k8s-\`)].LoadBalancerArn" \
          --output text 2>/dev/null | tr '\t' '\n' | while read -r arn; do
            [ -z "$arn" ] && continue
            TAGS=$(aws elbv2 describe-tags --region ${var.aws_region} --resource-arns "$arn" \
              --query 'TagDescriptions[0].Tags' --output json 2>/dev/null)
            echo "$TAGS" | grep -q "\"${var.cluster_name}\"" && \
              echo "$TAGS" | grep -q "\"${var.ingress_stack_tag}\"" && echo "$arn" && break
          done)
        if [ -n "$ARN" ]; then
          echo "ALB ready: $ARN"
          exit 0
        fi
        echo "  [$i/60] ALB 대기 중..."
        sleep 10
      done
      echo "ERROR: ALB가 10분 내에 프로비저닝되지 않음"
      exit 1
    EOT
  }
}

# ── Integration: HTTP_PROXY → Internal ALB Listener ────────────────
# request_parameters로 검증된 사용자 email을 x-user-email 헤더에 강제 주입
# overwrite:로 시작하면 클라이언트가 보낸 같은 헤더를 덮어씀 → 위조 불가
resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = data.aws_lb_listener.ingress.arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  payload_format_version = "1.0"

  request_parameters = {
    "overwrite:header.x-cognito-sub"   = "$context.authorizer.claims.sub"
    "overwrite:header.x-cognito-email" = "$context.authorizer.claims.email"
    "overwrite:header.x-cognito-name"  = "$context.authorizer.claims.name"
  }

  timeout_milliseconds = 29000
}

# ── 인증 필요한 routes (JWT Authorizer 적용) ──────────────────────
# /api/* 아래 모든 메서드 → Cognito 토큰 검증 후에만 통과
resource "aws_apigatewayv2_route" "api_authenticated" {
  for_each = toset([
    "ANY /api/{proxy+}",
  ])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.alb.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# ── 인증 우회 routes (헬스체크, 메트릭, 공개 조회) ─────────────────
# Prometheus가 외부에서 scrape할 수 있도록, /health도 ALB healthcheck용
# 이벤트/좌석 조회는 공개 정보이므로 비로그인도 둘러볼 수 있게 인증 면제
resource "aws_apigatewayv2_route" "api_public" {
  for_each = toset([
    "GET /health",
    "GET /event-metrics",
    "GET /reserv-metrics",
    "GET /worker-metrics",
    # 공개 조회: 영화
    "GET /api/read/movies",
    "GET /api/read/movies/detail/{movie_id}",
    "GET /api/read/movies/booking-bootstrap",
    "GET /api/read/movie/{movie_id}",
    # 공개 조회: 극장
    "GET /api/read/theaters",
    "GET /api/read/theaters/bootstrap",
    "GET /api/read/theaters/remain-overrides",
    "GET /api/read/theater/{theater_id}",
    # 공개 조회: 콘서트
    "GET /api/read/concerts",
    "GET /api/read/concert/{concert_id}",
    "GET /api/read/concert/{concert_id}/booking-bootstrap",
    "GET /api/read/concert/{concert_id}/booking-holds",
    # 공개: 헬스체크, 대기열, 예매상태 폴링
    "GET /api/read/health",
    "GET /api/read/waiting-room/{proxy+}",
    "GET /api/read/booking/{proxy+}",
    # 공개: write 쪽 대기열 상태 폴링 (queue_ref UUID 기반, 인증 대신 unguessable ref 로 보호)
    "GET /api/write/concerts/waiting-room/status/{queue_ref}",
    # CORS preflight
    "OPTIONS /api/{proxy+}",
  ])

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# ── Default Stage with auto-deploy ─────────────────────────────────
# $default 스테이지는 base path 없이 invoke URL 그대로 사용 가능
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 1000
    throttling_rate_limit  = 500
  }

  tags = { Name = "ticketing-http-api-default-stage", Environment = var.env }
}

# ── Internal ALB SG에서 VPC Link SG로부터의 inbound 허용 ───────────
# Internal ALB의 SG는 ALB Ingress Controller가 자동 생성하므로
# 우리는 'VPC Link SG에서 VPC 내부 0.0.0.0/16'으로 egress만 열어두면 됨
# (Internal ALB SG의 default behavior가 같은 VPC 내 HTTP를 받음)
