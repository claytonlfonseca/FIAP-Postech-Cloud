variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas para o Subnet Group do Redis."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security Groups (ex.: dos nodes EKS) autorizados a acessar o Redis."
  type        = list(string)
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "num_cache_clusters" {
  description = "Número de nós no replication group (1 = sem réplica)."
  type        = number
  default     = 1
}
