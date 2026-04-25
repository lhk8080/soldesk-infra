resource "aws_cognito_user_pool" "main" {
  name                     = "${var.app_name}-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 5
      max_length = 255
    }
  }

  lambda_config {
    pre_sign_up = var.pre_sign_up_lambda_arn
  }

  tags = { Name = "${var.app_name}-user-pool", Environment = var.env }
}

# Cognito가 Lambda를 호출할 수 있도록 권한 부여
resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.pre_sign_up_lambda_function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.app_name}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret               = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  access_token_validity  = 1
  refresh_token_validity = 7
  token_validity_units {
    access_token  = "hours"
    refresh_token = "days"
  }

  # 첫 apply 시 cloudfront_domain=""이면 localhost placeholder 사용 (cycle 차단)
  # CF 도메인 확정 후 재apply하면 실제 URL로 갱신
  callback_urls = [var.cloudfront_domain != "" ? "https://${var.cloudfront_domain}/callback" : "http://localhost:3000/callback"]
  logout_urls   = [var.cloudfront_domain != "" ? "https://${var.cloudfront_domain}/logout" : "http://localhost:3000/logout"]

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  allowed_oauth_flows_user_pool_client = true

  supported_identity_providers = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}
