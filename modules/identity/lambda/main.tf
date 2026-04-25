# Cognito pre_sign_up 트리거 — 이메일 인증 없이 회원가입 자동 확인
data "archive_file" "auto_confirm" {
  type        = "zip"
  output_path = "${path.module}/auto_confirm.zip"
  source {
    filename = "index.py"
    content  = <<-PYTHON
def handler(event, context):
    event['response']['autoConfirmUser'] = True
    event['response']['autoVerifyEmail'] = True
    return event
PYTHON
  }
}

resource "aws_iam_role" "auto_confirm" {
  name = "${var.app_name}-auto-confirm-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.auto_confirm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "auto_confirm" {
  function_name    = "${var.app_name}-auto-confirm"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.auto_confirm.arn
  filename         = data.archive_file.auto_confirm.output_path
  source_code_hash = data.archive_file.auto_confirm.output_base64sha256
}
