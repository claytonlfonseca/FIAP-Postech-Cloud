output "bucket_name" {
  description = "Nome do bucket criado para o backend remoto do Terraform."
  value       = aws_s3_bucket.tfstate.bucket
}
