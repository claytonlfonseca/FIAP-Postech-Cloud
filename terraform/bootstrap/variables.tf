variable "region" {
  description = "Região AWS onde o bucket de state será criado."
  type        = string
  default     = "us-east-2"
}

variable "bucket_name" {
  description = "Nome (globalmente único) do bucket S3 para o terraform.tfstate."
  type        = string
  default     = "togglemaster-tfstate-account_id"
}
