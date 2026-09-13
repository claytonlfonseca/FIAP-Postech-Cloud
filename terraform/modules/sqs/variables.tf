variable "queue_name" {
  type    = string
  default = "toggle-master-events"
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 dias
}
