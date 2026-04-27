terraform {
  required_version = ">= 1.6"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    helm       = { source = "hashicorp/helm", version = "~> 2.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
  backend "s3" {
    # terraform init -backend-config="bucket=<tfstate-bucket>" -backend-config="region=<region>"
    key = "k8s/terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}
