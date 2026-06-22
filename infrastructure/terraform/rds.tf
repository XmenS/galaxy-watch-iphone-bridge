resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_kms_key" "rds" {
  description             = "${local.name} RDS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_db_instance" "main" {
  identifier              = "${local.name}-pg"
  engine                  = "postgres"
  engine_version          = "16.4"
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage_gb
  max_allocated_storage   = var.db_allocated_storage_gb * 4
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = aws_kms_key.rds.arn
  db_name                 = "ghb"
  username                = "ghb"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  multi_az                = true
  backup_retention_period = 14
  deletion_protection     = true
  performance_insights_enabled = true
  monitoring_interval     = 60
  auto_minor_version_upgrade = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "${local.name}-pg-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
}

resource "aws_secretsmanager_secret" "db_url" {
  name        = "${local.name}/database_url"
  description = "DATABASE_URL for the API"
  kms_key_id  = aws_kms_key.rds.arn
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id = aws_secretsmanager_secret.db_url.id
  secret_string = "postgresql+asyncpg://${aws_db_instance.main.username}:${random_password.db.result}@${aws_db_instance.main.endpoint}/ghb"
}

# ---- Redis
resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name}-cache"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id        = "${local.name}-redis"
  description                 = "Galaxy Health Bridge Redis"
  engine                      = "redis"
  engine_version              = "7.1"
  node_type                   = "cache.t4g.small"
  num_cache_clusters          = 2
  automatic_failover_enabled  = true
  multi_az_enabled            = true
  subnet_group_name           = aws_elasticache_subnet_group.main.name
  security_group_ids          = [aws_security_group.cache.id]
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  apply_immediately           = false
}
