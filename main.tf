// Ensure VAULT_ADDR and VAULT_TOKEN env vars are set
provider "vault" {
  version = "1.7.0"
}

resource "vault_mount" "database" {
  path                      = "database"
  type                      = "database"
  default_lease_ttl_seconds = "${local.database["lease_ttl"]}"
  max_lease_ttl_seconds     = "${local.database["lease_ttl"]}"
}

resource "vault_database_secret_backend_connection" "postgres" {
  allowed_roles = ["service-write", "dev-read"]
  backend       = "${vault_mount.database.path}"
  name          = "postgres-secret-backend"

  // Needed as SSL is disabled on postgres Docker container
  verify_connection = false

  postgresql {
    // sslmode=disable needed for the Postgres Go Client
    connection_url = "postgres://${var.db_user}:${var.db_password}@${var.db_endpoint}/${var.db}?sslmode=disable"
  }
}

resource "vault_database_secret_backend_role" "postgres_service_write" {
  backend = "${vault_mount.database.path}"
  name    = "service-write"
  db_name = "${vault_database_secret_backend_connection.postgres.name}"

  creation_statements = <<EOF
    CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}';
    GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO "{{name}}";
  EOF

  revocation_statements = <<EOF
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM "{{name}}";
    DROP ROLE "{{name}}";
  EOF

  default_ttl = 864000 // 10 days
  max_ttl     = 864000 // 10 days
}

resource "vault_database_secret_backend_role" "postgres_dev_read" {
  backend = "${vault_mount.database.path}"
  name    = "dev-read"
  db_name = "${vault_database_secret_backend_connection.postgres.name}"

  creation_statements = <<EOF
    CREATE ROLE "{{name}}" WITH LOGIN PASSWORD '{{password}}';
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO "{{name}}";
  EOF

  revocation_statements = <<EOF
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM "{{name}}";
    DROP ROLE "{{name}}";
  EOF

  default_ttl = 2592000 // 30 days
  max_ttl     = 2592000 // 30 days
}
