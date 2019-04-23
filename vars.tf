variable postgres_db {
  default = "postgres"
}

variable postgres_db_endpoint {
  default     = "database:5432"
  description = "DB endpoint from Vault server point of view. Using compose DNS entry"
}

variable postgres_db_password {}

variable postgres_db_user {}
