data "aws_availability_zones" "available" {
  state = "available"
}

# 단일 VPC에 서브넷/태그로 Public(웹·WAS) / Private(DB) 계층 구분
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = "Public_VPC"
    Environment = var.env
    Layer       = "web-was-data-colocated"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "IGW"
    Environment = var.env
  }
}

# Pod ENI 전용 Secondary CIDR (EKS VPC Custom Networking)
# - 기존 10.0.x.x public 서브넷의 IP 고갈 방지 목적
# - 파드 ENI는 이 대역(100.64.0.0/16)에서 IP를 받고, 노드 primary ENI는 10.0.x.x 유지
# - RFC6598(CGNAT) 대역 사용: 흔한 사설 대역 충돌 없음, AWS EKS 공식 가이드 표준 예시
resource "aws_vpc_ipv4_cidr_block_association" "pod" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "100.64.0.0/16"
}

# VPC destroy 직전 K8s/ALB 컨트롤러가 남긴 ENI·VPC Endpoint·SG 정리
# Terraform 관리 SG는 건드리지 않고 k8s 생성 아티팩트만 삭제
resource "null_resource" "cleanup_vpc_leftovers_before_destroy" {
  triggers = {
    vpc_id = aws_vpc.main.id
    region = var.aws_region
  }

  depends_on = [aws_vpc.main]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    when        = destroy
    environment = {
      NET_VPC_ID = self.triggers.vpc_id
      NET_REGION = self.triggers.region
      AWS_PAGER  = ""
    }
    command = "tr -d '\\r' < \"${path.module}/scripts/cleanup_vpc_leftovers_before_destroy.sh\" | bash"
  }
}
