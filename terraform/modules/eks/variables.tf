variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "cluster_version" {
  description = "Versão do Kubernetes do cluster EKS."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster será criado."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets (privadas recomendadas) usadas pelo cluster e node group."
  type        = list(string)
}

variable "node_instance_types" {
  description = "Tipos de instância EC2 usados pelo node group."
  type        = list(string)
  default     = ["t3.micro"]
}

variable "desired_size" {
  description = "Número desejado de nodes."
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Número mínimo de nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Número máximo de nodes."
  type        = number
  default     = 3
}
