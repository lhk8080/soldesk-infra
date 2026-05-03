resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "ticketing-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  web_acl_id          = var.waf_acl_arn
  price_class         = "PriceClass_200"
  wait_for_deployment = true

  aliases = var.aliases

  # destroy 전 distribution 비활성화 + 전파 대기 — 없으면 OAC 삭제 시 "OriginAccessControlInUse" 에러
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    environment = {
      AWS_PAGER = ""
    }
    command = <<-EOT
      set +e
      DIST_ID="${self.id}"

      ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" \
        --query 'ETag' --output text 2>&1)
      if [ $? -ne 0 ]; then
        echo "CloudFront distribution을 찾을 수 없음 (이미 삭제됨). 스킵합니다."
        exit 0
      fi

      if [ -n "$ETAG" ] && [ "$ETAG" != "None" ]; then
        CF_TMP=$(mktemp)
        trap 'rm -f "$CF_TMP"' EXIT

        aws cloudfront get-distribution-config --id "$DIST_ID" \
          --query 'DistributionConfig' > "$CF_TMP"

        python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cfg = json.load(f)
cfg['Enabled'] = False
with open(sys.argv[1], 'w') as f:
    json.dump(cfg, f)
" "$CF_TMP"

        CF_TMP_PATH="$CF_TMP"
        if command -v cygpath >/dev/null 2>&1; then
          CF_TMP_PATH=$(cygpath -m "$CF_TMP")
        fi

        aws cloudfront update-distribution \
          --id "$DIST_ID" \
          --distribution-config "file://$CF_TMP_PATH" \
          --if-match "$ETAG" > /dev/null || true

        aws cloudfront wait distribution-deployed --id "$DIST_ID" || true
      fi
    EOT
  }

  # Origin 1: S3 정적 프론트엔드
  origin {
    domain_name              = var.frontend_domain
    origin_id                = "S3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Origin 2: API Gateway — endpoint가 비어있으면 생략
  dynamic "origin" {
    for_each = var.api_gateway_endpoint_host != "" ? [var.api_gateway_endpoint_host] : []
    content {
      domain_name = origin.value
      origin_id   = "APIGW-api"
      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # 기본 캐시: SPA (S3)
  default_cache_behavior {
    target_origin_id       = "S3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  # /api/* 캐시: API GW origin이 있을 때만 생성, 캐싱 없음
  # Authorization 헤더 forward 필수 — JWT Authorizer 검증에 필요
  dynamic "ordered_cache_behavior" {
    for_each = var.api_gateway_endpoint_host != "" ? [1] : []
    content {
      path_pattern           = "/api/*"
      target_origin_id       = "APIGW-api"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      forwarded_values {
        query_string = true
        headers      = ["Authorization", "Content-Type", "CloudFront-Forwarded-Proto"]
        cookies { forward = "none" }
      }

      min_ttl     = 0
      default_ttl = 0
      max_ttl     = 0
    }
  }

  # SPA 라우팅: S3 404 → index.html 200
  # 403은 rewrite 안 함 — WAF 차단 시 JS 파일에 HTML 응답이 캐싱되는 문제 방지
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = length(var.aliases) == 0
    acm_certificate_arn            = length(var.aliases) > 0 ? var.acm_certificate_arn : null
    ssl_support_method             = length(var.aliases) > 0 ? "sni-only" : null
    minimum_protocol_version       = length(var.aliases) > 0 ? "TLSv1.2_2021" : null
  }

  tags = { Name = "ticketing-cloudfront", Environment = var.env }
}

# S3 버킷 정책: CloudFront OAC만 접근 허용
resource "aws_s3_bucket_policy" "frontend" {
  bucket = var.frontend_bucket_id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${var.frontend_bucket_arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
        }
      }
    }]
  })
}
