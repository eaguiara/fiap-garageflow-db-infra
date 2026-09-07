variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "Região da AWS"
}

variable "sql_db_name" {
  default     = "garage-flow"
  description = "Nome do banco de dados SQL Server"
}

variable "sql_db_user" {
  default     = "garage_flow"
  description = "Usuário padrão do banco"
}

variable "sql_db_password" {
  type        = string
  sensitive   = true
  description = "Senha padrão do banco"
}

variable "allowed_db_cidr_blocks" {
  type        = list(string)
  description = "CIDRs das subnets privadas autorizadas a acessar o SQL Server"
  default     = ["10.0.0.0/16"]
}

variable "cluster_name" {
  description = "Name of the local Kubernetes cluster created with kind."
  type        = string
  default     = "garageflow"
}