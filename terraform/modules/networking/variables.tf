variable "name" {
  description = "Prefixo usado para nomear os recursos de rede."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Mapa (índice => CIDR) das subnets públicas."
  type        = map(string)
  default = {
    "0" = "10.0.0.0/24"
    "1" = "10.0.1.0/24"
  }
}

variable "private_subnet_cidrs" {
  description = "Mapa (índice => CIDR) das subnets privadas."
  type        = map(string)
  default = {
    "0" = "10.0.10.0/24"
    "1" = "10.0.11.0/24"
  }
}

variable "enable_nat_gateway" {
  description = "Se true, cria um NAT Gateway único para as subnets privadas."
  type        = bool
  default     = true
}
