# 웹 공용 서브넷 (ALB, EKS 노드, 모니터링)
# - 4개로 확장: EKS Pod IP 소비가 커서 /24 2개만으로는 burst 시 IP 고갈 발생
# - AZ는 2a/2b 안에서만 번갈아 배치 (클러스터 생성 시점 AZ 집합 고정 제약)
resource "aws_subnet" "public" {
  count                   = 4
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index % 2]
  map_public_ip_on_launch = true
  tags = {
    Name                                            = "Public_VPC_Web_Pub_RT_SN${count.index + 1}"
    Environment                                     = var.env
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

# DB·캐시용 프라이빗 서브넷
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "Private_VPC_DB_Pri_RT_SN${count.index + 1}"
    Environment = var.env
    Layer       = "db"
  }
}

# Pod 전용 서브넷 (/18 = 16,384 IP, prefix delegation /28 기준 최대 1,024 prefix)
# - kubernetes.io/cluster / kubernetes.io/role 태그 없음: ALB 컨트롤러 자동 탐색 대상 제외
# - map_public_ip_on_launch = false: 파드 직노출 금지
resource "aws_subnet" "pod" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "100.64.${count.index * 64}.0/18"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  depends_on              = [aws_vpc_ipv4_cidr_block_association.pod]
  tags = {
    Name        = "Pod_Subnet_${count.index + 1}_AZ${count.index + 1}"
    Environment = var.env
    Tier        = "pods"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name        = "Public_VPC_Web_Pub_RT"
    Environment = var.env
  }
}

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = "Private_VPC_DB_Pri_RT"
    Environment = var.env
  }
}

resource "aws_route_table_association" "public" {
  count          = 4
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# Pod 서브넷은 public RT 재사용 (IGW 경로 있어도 pod ENI에 public IP 없어 직접 노출 없음)
resource "aws_route_table_association" "pod" {
  count          = 2
  subnet_id      = aws_subnet.pod[count.index].id
  route_table_id = aws_route_table.public.id
}
