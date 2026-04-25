terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.0" }
    null   = { source = "hashicorp/null", version = "~> 3.0" }
    tls    = { source = "hashicorp/tls", version = "~> 4.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.0" }
  }
  backend "s3" {
    # terraform init -backend-config="bucket=<tfstate-bucket>" -backend-config="region=<region>"
    key = "infra/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# WAF는 CLOUDFRONT scope이므로 us-east-1 전용
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
