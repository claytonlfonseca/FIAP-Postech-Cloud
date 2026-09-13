output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_role_arn" {
  value = module.eks.cluster_role_arn
}

output "eks_node_role_arn" {
  value = module.eks.node_role_arn
}

output "rds_endpoints" {
  value = module.rds.endpoints
}

output "rds_secret_arns" {
  description = "ARNs no Secrets Manager com as credenciais master de cada RDS (geradas pela AWS)."
  value       = module.rds.secret_arns
}

output "redis_primary_endpoint" {
  value = module.elasticache.primary_endpoint_address
}

output "redis_auth_token" {
  value     = module.elasticache.auth_token
  sensitive = true
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}
