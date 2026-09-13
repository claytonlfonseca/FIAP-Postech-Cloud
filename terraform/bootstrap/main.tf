##############################################
# Bootstrap: cria o bucket S3 usado como
# backend remoto do Terraform (estado + lock).
# Rode este projeto UMA VEZ, com backend local,
# antes de aplicar o projeto principal (../).
##############################################

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ToggleMaster"
      ManagedBy   = "Terraform"
      Environment = "bootstrap"
    }
  }
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  # Evita destruir o bucket de estado por engano (contém histórico do state).
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
