# Web_SG: ALB / 모니터링 서버용 퍼블릭 SG
resource "aws_security_group" "web" {
  name        = "prod-monitoring-sg"
  vpc_id      = aws_vpc.main.id
  description = "EC2 monitoring server security group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Prometheus / Alertmanager"
    from_port   = 9090
    to_port     = 9093
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "Web_SG"
    Environment = var.env
  }
}

# WAS_SG: EKS 워커 노드 SG
resource "aws_security_group" "was" {
  name        = "prod-eks-sg"
  vpc_id      = aws_vpc.main.id
  description = "EKS worker node security group"

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }
  ingress {
    description = "Kubernetes API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "WAS_SG"
    Environment = var.env
  }
}

# DB_SG: RDS Aurora — 순환 참조 방지를 위해 인라인 규칙 없이 rule 리소스로 분리
resource "aws_security_group" "db" {
  name        = "prod-rds-sg"
  vpc_id      = aws_vpc.main.id
  description = "RDS Aurora SG - allow from EKS only"

  tags = {
    Name        = "DB_SG"
    Environment = var.env
  }
}

resource "aws_security_group_rule" "db_icmp" {
  type              = "ingress"
  description       = "ICMP from VPC"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  security_group_id = aws_security_group.db.id
  cidr_blocks       = ["10.0.0.0/16"]
}

resource "aws_security_group_rule" "db_from_was" {
  type                     = "ingress"
  description              = "MySQL from WAS"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.was.id
}

resource "aws_security_group_rule" "db_ssh_from_web" {
  type                     = "ingress"
  description              = "SSH from Web_SG"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = aws_security_group.web.id
}

resource "aws_security_group_rule" "db_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.db.id
  cidr_blocks       = ["0.0.0.0/0"]
}

# Cache_SG: ElastiCache Redis
resource "aws_security_group" "cache" {
  name        = "Cache_SG"
  vpc_id      = aws_vpc.main.id
  description = "ElastiCache Redis from WAS only"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "Cache_SG"
    Environment = var.env
  }
}

resource "aws_security_group_rule" "cache_from_was" {
  type                     = "ingress"
  description              = "Redis from WAS"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cache.id
  source_security_group_id = aws_security_group.was.id
}

resource "aws_security_group_rule" "cache_from_monitoring" {
  type                     = "ingress"
  description              = "Redis from Monitoring"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cache.id
  source_security_group_id = aws_security_group.web.id
}
