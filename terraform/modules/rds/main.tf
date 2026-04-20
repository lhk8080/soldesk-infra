terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# RDS 마스터 비번은 모듈이 직접 생성. tfvars 평문 입력 폐지.
# state 안에는 여전히 평문으로 보관되지만, 외부 SSM Parameter Store에 SecureString으로
# 저장되어 ESO를 통해 K8s Secret으로 주입된다.
# 비번 회전 시: random_password.db.keepers를 변경하여 새 값 강제 생성.
resource "random_password" "db" {
  length  = 24
  special = true
  # RDS는 / @ " 등 일부 특수문자를 거부 → 호환되는 집합만 허용
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "main" {
  name       = "prod-rds-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "prod-rds-subnet-group", Environment = var.env }
}

# Primary (Writer) - db.t3.micro MySQL
resource "aws_db_instance" "writer" {
  identifier        = "prod-ticketing-writer"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "ticketing"
  username = "root"
  password = random_password.db.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]

  multi_az                = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  tags = { Name = "ticketing-mysql-writer", Role = "primary", Environment = var.env }
}

# Read Replica (Reader) - db.t3.micro
resource "aws_db_instance" "reader" {
  identifier          = "prod-ticketing-reader"
  replicate_source_db = aws_db_instance.writer.identifier
  instance_class      = "db.t3.micro"

  skip_final_snapshot = true
  deletion_protection = false

  tags = { Name = "ticketing-mysql-reader", Role = "replica", Environment = var.env }
}
