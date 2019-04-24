variable db {
  default = "postgres"
}

variable db_endpoint {
  default     = "database:5432"
  description = "DB endpoint from Vault server point of view. Using compose DNS entry"
}

variable db_password {}

variable db_user {}
