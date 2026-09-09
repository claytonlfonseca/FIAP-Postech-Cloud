variable "table_name" {
  type    = string
  default = "ToggleMasterAnalytics"
}

variable "hash_key" {
  type    = string
  default = "eventId"
}

variable "range_key" {
  type    = string
  default = "timestamp"
}
