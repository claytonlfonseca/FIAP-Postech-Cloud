terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend remoto: bucket criado previamente em terraform/bootstrap.
  # Preencha bucket/key/region reais via `terraform init -backend-config=...`
  # ou complete os valores abaixo (não use variáveis aqui: bloco backend
  # não aceita interpolação).
  backend "s3" {
    bucket       = "togglemaster-tfstate-052005814846"
    key          = "togglemaster/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "ToggleMaster"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}
