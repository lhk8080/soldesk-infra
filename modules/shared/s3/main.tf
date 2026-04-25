resource "aws_s3_bucket" "frontend" {
  bucket        = "ticketing-frontend-${var.aws_account}"
  force_destroy = true
  tags          = { Name = "ticketing-frontend", Environment = var.env, Purpose = "frontend" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "assets" {
  bucket        = "ticketing-assets-${var.aws_account}"
  force_destroy = true
  tags          = { Name = "ticketing-assets", Environment = var.env, Purpose = "assets" }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
