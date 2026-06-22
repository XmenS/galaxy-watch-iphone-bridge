output "alb_dns_name" {
  value       = aws_lb.api.dns_name
  description = "Point DNS CNAME for var.domain_name at this value"
}

output "rds_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}

output "redis_primary_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "s3_blobs_bucket" {
  value = aws_s3_bucket.blobs.id
}

output "ecr_image_api" {
  value = var.api_image
}
