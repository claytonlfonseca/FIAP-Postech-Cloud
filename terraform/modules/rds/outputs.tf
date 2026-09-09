output "security_group_id" {
  value = aws_security_group.rds.id
}

output "endpoints" {
  description = "Endpoints de conexão por serviço."
  value       = { for k, v in aws_db_instance.this : k => v.endpoint }
}

output "secret_arns" {
  description = "ARNs dos segredos (Secrets Manager) com as credenciais master geradas pela AWS, por serviço."
  value       = { for k, v in aws_db_instance.this : k => v.master_user_secret[0].secret_arn }
}
