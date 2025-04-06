resource "aws_db_subnet_group" "main" {
  name        = "dify"
  description = "PostgreSQL for Dify"
  subnet_ids  = var.private_subnet_ids
}

resource "aws_rds_cluster" "main" {
  cluster_identifier = "dify"

  engine         = "aurora-postgresql"
  engine_version = "15.4"
  port           = 5432

  db_subnet_group_name            = aws_db_subnet_group.main.name
  db_cluster_parameter_group_name = "default.aurora-postgresql15"
  vpc_security_group_ids          = var.security_group_ids

  master_username = "postgres"
  master_password = var.db_master_password

  # データベースは後から構築する
  # -- CREATE ROLE dify WITH LOGIN PASSWORD 'password';
  # -- GRANT dify TO postgres;
  # -- CREATE DATABASE dify WITH OWNER dify;
  # -- \c dify
  # -- CREATE EXTENSION vector;

  # 上記 SQL をマネジメントコンソールのクエリエディタで実行する場合は HTTP エンドポイントを有効にする。
  # エンドポイントを有効にしない場合は踏み台インスタンスなどを用意して上記 SQL を実行する。
  enable_http_endpoint = true

  backup_retention_period  = 7
  delete_automated_backups = true

  preferred_backup_window      = "13:29-13:59"
  preferred_maintenance_window = "sat:18:00-sat:19:00"
  skip_final_snapshot          = true
  storage_encrypted            = true
  copy_tags_to_snapshot        = true

  serverlessv2_scaling_configuration {
    min_capacity = 2
    max_capacity = 4
  }

  lifecycle {
    ignore_changes = [engine_version, master_password]
  }
}

resource "aws_rds_cluster_instance" "main" {
  identifier = "dify-instance-1"

  cluster_identifier = aws_rds_cluster.main.cluster_identifier
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version
  instance_class     = "db.serverless"

  auto_minor_version_upgrade = true
  promotion_tier             = 1

  db_parameter_group_name = "default.aurora-postgresql15"
  db_subnet_group_name    = aws_db_subnet_group.main.name

  performance_insights_enabled          = true
  performance_insights_retention_period = 7
}
