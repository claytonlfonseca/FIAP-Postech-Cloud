output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "security_group_id" {
  value = aws_security_group.redis.id
}

output "auth_token" {
  value     = random_password.auth_token.result
  sensitive = true
}
