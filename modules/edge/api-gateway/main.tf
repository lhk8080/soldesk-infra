# 흐름: CloudFront → API Gateway (Cognito JWT Authorizer) → VPC Link → Internal ALB → EKS
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

# Authorization 헤더의 JWT 토큰을 Cognito로 자동 검증
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

# API Gateway → Internal ALB 연결 통로 (v2: ALB 직접 지원)
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

# alb_listener_arn이 비어있으면 첫 apply 시 생성 안 함 (chicken-and-egg 방지)
# 두 번째 apply 시 listener ARN을 tfvars에 넣으면 자동 생성
resource "aws_apigatewayv2_integration" "alb" {
  count = var.alb_listener_arn != "" ? 1 : 0

  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = var.alb_listener_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  payload_format_version = "1.0"

  # 검증된 Cognito claims를 헤더로 주입 (overwrite: 로 클라이언트 위조 차단)
  request_parameters = {
    "overwrite:header.x-cognito-sub"   = "$context.authorizer.claims.sub"
    "overwrite:header.x-cognito-email" = "$context.authorizer.claims.email"
    "overwrite:header.x-cognito-name"  = "$context.authorizer.claims.name"
  }

  timeout_milliseconds = 29000
}

# 인증 필요 routes — /api/* 전체
resource "aws_apigatewayv2_route" "api_authenticated" {
  for_each = var.alb_listener_arn != "" ? toset([
    "ANY /api/{proxy+}",
  ]) : toset([])

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.value
  target             = "integrations/${aws_apigatewayv2_integration.alb[0].id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# 인증 우회 routes — 헬스체크, 메트릭, 공개 조회, CORS preflight
resource "aws_apigatewayv2_route" "api_public" {
  for_each = var.alb_listener_arn != "" ? toset([
    "GET /health",
    "GET /event-metrics",
    "GET /reserv-metrics",
    "GET /worker-metrics",
    "GET /api/read/movies",
    "GET /api/read/movies/detail/{movie_id}",
    "GET /api/read/movies/booking-bootstrap",
    "GET /api/read/movie/{movie_id}",
    "GET /api/read/theaters",
    "GET /api/read/theaters/bootstrap",
    "GET /api/read/theaters/remain-overrides",
    "GET /api/read/theater/{theater_id}",
    "GET /api/read/concerts",
    "GET /api/read/concert/{concert_id}",
    "GET /api/read/concert/{concert_id}/booking-bootstrap",
    "GET /api/read/concert/{concert_id}/booking-holds",
    "GET /api/read/health",
    "GET /api/read/version",
    "GET /api/read/waiting-room/{proxy+}",
    "GET /api/read/booking/{proxy+}",
    "POST /api/write/concerts/{show_id}/waiting-room/enter",
    "GET /api/write/concerts/waiting-room/status/{queue_ref}",
    "OPTIONS /api/{proxy+}",
  ]) : toset([])

  api_id    = aws_apigatewayv2_api.main.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.alb[0].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10000
    throttling_rate_limit  = 5000
  }

  tags = { Name = "ticketing-http-api-default-stage", Environment = var.env }
}
