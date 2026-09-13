variable "repository_names" {
  description = "Lista dos microsserviços que terão repositório no ECR."
  type        = list(string)
  default     = ["auth", "flag", "targeting", "evaluation", "analytics"]
}
