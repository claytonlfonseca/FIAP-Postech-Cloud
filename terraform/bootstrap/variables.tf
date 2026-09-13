variable "region" {
  description = "Região AWS onde o bucket de state será criado."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Nome (globalmente único) do bucket S3 para o terraform.tfstate."
  type        = string
  default     = "togglemaster-tfstate-052005814846"
}
