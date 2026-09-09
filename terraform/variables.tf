variable "region" {
  description = "Região AWS."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente (dev, hml, prod)."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos."
  type        = string
  default     = "togglemaster"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "eks_cluster_version" {
  type    = string
  default = "1.30"
}

variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t3.micro"]
}

variable "eks_desired_size" {
  type    = number
  default = 2
}

variable "eks_min_size" {
  type    = number
  default = 1
}

variable "eks_max_size" {
  type    = number
  default = 3
}

variable "rds_databases" {
  description = "Bancos PostgreSQL a serem criados (1 por serviço)."
  type = map(object({
    db_name = string
  }))
  default = {
    auth      = { db_name = "auth" }
    flag      = { db_name = "flagdb" }
    targeting = { db_name = "targeting" }
  }
}

variable "ecr_repository_names" {
  type    = list(string)
  default = ["auth", "flag", "targeting", "evaluation", "analytics"]
}

variable "sqs_queue_name" {
  type    = string
  default = "toggle-master-events"
}

variable "dynamodb_table_name" {
  type    = string
  default = "ToggleMasterAnalytics"
}
