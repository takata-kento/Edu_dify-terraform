resource "aws_elasticache_subnet_group" "main" {
  name        = "dify-redis"
  description = "Redis for Dify"
  subnet_ids  = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "dify"
  description          = "Redis for Dify"

  engine         = "redis"
  engine_version = "7.1"

  node_type = "cache.t4g.micro"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = var.security_group_ids

  auto_minor_version_upgrade = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  auth_token_update_strategy = "SET"
  auth_token                 = var.redis_password

  maintenance_window       = "sat:18:00-sat:19:00"
  snapshot_window          = "20:00-21:00"
  snapshot_retention_limit = 1

  parameter_group_name = "default.redis7"
}
