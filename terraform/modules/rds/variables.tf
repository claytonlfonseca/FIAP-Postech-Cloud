variable "name_prefix" {
  description = "Prefixo usado para nomear os recursos RDS."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets privadas para o DB Subnet Group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security Groups (ex.: dos nodes EKS) autorizados a acessar o RDS."
  type        = list(string)
}

variable "databases" {
  description = "Mapa de bancos a serem criados: chave = identificador do serviço, valor = { db_name }."
  type = map(object({
    db_name = string
  }))
  default = {
    auth      = { db_name = "auth" }
    flag      = { db_name = "flagdb" }
    targeting = { db_name = "targeting" }
  }
}

variable "master_username" {
  description = "Usuário master do PostgreSQL."
  type        = string
  default     = "toggle_admin"
}

variable "engine_version" {
  description = "Versão do PostgreSQL."
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Classe de instância RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento (GB) alocado para cada instância."
  type        = number
  default     = 20
}
