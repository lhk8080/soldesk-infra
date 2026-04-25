resource "aws_elasticache_subnet_group" "main" {
  name       = "ticketing-redis-subnet-group"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "ticketing-redis"
  description          = "Ticketing ElastiCache Redis single-node cache"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = var.node_type
  port                 = 6379

  # 비용 최소화: 단일 노드, 복제/다중AZ 비활성
  num_cache_clusters         = 1
  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [var.security_group_id]

  snapshot_retention_limit = 0

  tags = { Name = "ticketing-redis", Environment = var.env }
}
