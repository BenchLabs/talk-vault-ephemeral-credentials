# Ephemeral database credentials with Vault and Terraform

Technical demo for the [Vancouver Hashicorp User Group spring time 
meetup](https://www.meetup.com/Vancouver-HashiCorp-User-Group/events/260290519).


## Requirements

- `docker-compose` with Compose [file format version](https://github.com/docker/compose/releases) 3 support or greater
- `terraform` client: https://www.terraform.io/downloads.html
- `vault` client: https://www.vaultproject.io/downloads.html

## Abstract

The idea of this demo is to generate database ephemeral credentials using Vault 
[PostgreSQL Database Secrets Engine](https://www.vaultproject.io/docs/secrets/databases/postgresql.html).

The demo uses `docker-compose` to run Vault + PostgreSQL servers locally and the Terraform 
[vault_database_secret_backend](https://www.terraform.io/docs/providers/vault/r/database_secret_backend_role.html) to manage all the necessary roles, connections and Vault 
configuration in a codified way.
 
In this example we will provision two secret backend roles, one called `service-write` that would grant 
database write access to a service and another one called `dev-read` that would grant read-only access to a
 developer.

Each role has a different TTL which is the length of the credentials.


## Usage

### Generating Vault server root token

In production you would authenticate with your Vault server which will result on your `VAULT_TOKEN` 
environment variable being set. 

For this demo, let's just generate a random token and use it for both `terraform` and `docker-compose` 
commands: 

```bash
# Generate root token
ROOT_TOKEN=$(uuidgen)
echo "${ROOT_TOKEN}"

# Export VAULT_TOKEN and VAULT_ADDR
export VAULT_TOKEN=$ROOT_TOKEN
export VAULT_ADDR="http://0.0.0.0:8200"
```

### Starting up docker-compose

First, ensure `VAULT_TOKEN` is set. This is very important as we pass our generated `VAULT_TOKEN` to the vault
 server running on `docker-compose`.
 
 ```bash
env | grep -i vault
# Should return something like
VAULT_TOKEN=D8B5D80D-8FCE-4723-92F3-8CC602A1B027
VAULT_ADDR=http://0.0.0.0:8200
```

Then just run `docker-compose up` - this will start up both the Postgres and Vault server containers.


### Generating credentials

#### Terraform pre-reqs

Add a file like the following to store database root credentials which will be used by Vault to generate 
ephemeral ones. While we use the Docker Postgres defaults, it's always a good idea to follow this approach 
for sensitive information:

**terraform.tfvars**

```hcl
postgres_db_password = "password"
postgres_db_user = "postgres"
```

This demo will store state on a local file named `terraform.tfstate` but it's recommended to use a Remote 
State for real projects. More information on Terraform remote state [here](https://www.terraform.io/docs/state/remote.html).

#### Terraform init and plan

Run: `terraform init`

Then, make sure `VAULT_TOKEN` and `VAULT_ADDR` are set, this is to ensure the [Vault Terraform Provider](https://www.terraform.io/docs/providers/vault/index.html)
is able to interact with your vault server running on `docker-compose`

 ```bash
env | grep -i vault
# Should return something like
VAULT_TOKEN=D8B5D80D-8FCE-4723-92F3-8CC602A1B027
VAULT_ADDR=http://0.0.0.0:8200
```

If the env vars are not present, just export them. Do not use `uuidgen` this time as the `VAULT_TOKEN` 
should be the same one as the one passed to `docker-compose`:

```bash
export VAULT_TOKEN="D8B5D80D-8FCE-4723-92F3-8CC602A1B027"
export VAULT_ADDR="http://0.0.0.0:8200"
```

Then run `terraform plan` which should generate an execution plan similar to the following:

```bash
Terraform will perform the following actions:

  + vault_database_secret_backend_connection.postgres
      id:                                <computed>
      allowed_roles.#:                   "2"
      allowed_roles.0:                   "service-write"
      allowed_roles.1:                   "dev-read"
      backend:                           "database"
      name:                              "postgres-secret-backend"
      postgresql.#:                      "1"
      postgresql.0.connection_url:       "postgres://postgres:password@database:5432/postgres?sslmode=disable"
      postgresql.0.max_open_connections: "2"
      verify_connection:                 "false"

  + vault_database_secret_backend_role.postgres_dev_read
      id:                                <computed>
      backend:                           "database"
      creation_statements:               REDACTED
      db_name:                           "postgres-secret-backend"
      default_ttl:                       "2592000"
      max_ttl:                           "2592000"
      name:                              "dev-read"
      revocation_statements:             REDACTED

  + vault_database_secret_backend_role.postgres_service_write
      id:                                <computed>
      backend:                           "database"
      creation_statements:               REDACTED
      db_name:                           "postgres-secret-backend"
      default_ttl:                       "864000"
      max_ttl:                           "864000"
      name:                              "service-write"
      revocation_statements:             REDACTED

  + vault_mount.database
      id:                                <computed>
      accessor:                          <computed>
      default_lease_ttl_seconds:         "2592000"
      max_lease_ttl_seconds:             "2592000"
      path:                              "database"
      type:                              "database"


Plan: 4 to add, 0 to change, 0 to destroy.
```

#### Terraform apply

If the `terraform plan` output looks similar to the above one then run `terraform apply` to create the 
resources.


#### Trying it out


After applying the changes, we should be able to use vault CLI to interact with our newly created database 
secret backend:

```bash
# Ensure `VAULT_TOKEN` and `VAULT_ADDR` are set for this work!
vault read database/config/postgres-secret-backend

Key                                   Value
---                                   -----
allowed_roles                         [service-write dev-read]
connection_details                    map[connection_url:postgres://postgres:*****@database:5432/postgres?sslmode=disable max_open_connections:2]
plugin_name                           postgresql-database-plugin
```

##### Use write credentials

First generate a new set of creds with vault:

```bash
vault read database/creds/service-write

Key                Value
---                -----
lease_id           database/creds/service-write/lVpzrysA5akqSvjZVtCgx1i9
lease_duration     240h
lease_renewable    true
password           A1a-9yW06ZdVk54I5KnX
username           v-token-service--1luYzAYl7SdMxvdpibYv-1555972312
```

Then use them to login into your local Postgres database and make some changes:

```bash
psql -h localhost -U v-token-service--1luYzAYl7SdMxvdpibYv-1555972312 -W -d postgres

CREATE TABLE test_table (
             product_no integer,
             name text,
             price numeric
         );
INSERT INTO test_table VALUES (1, 'Cheese', 9.99);

SELECT * FROM test_table;

\dt;
```

You can also view your newly created user when running `\du;`

##### Use read credentials

Generate new creds and use them:
```bash
vault read database/creds/dev-read
Key                Value
---                -----
lease_id           database/creds/dev-read/TLCjNu5vT73r0QCW6X86f26Z
lease_duration     720h
lease_renewable    true
password           A1a-GiwY6h7CHbsMHLLL
username           v-token-analytic-09puAVVxuQm6ELgrIMXT-1555973788
```

```bash
psql -h localhost -U v-token-analytic-09puAVVxuQm6ELgrIMXT-1555973788 -W -d postgres

# We can SELECT but not INSERT
SELECT * FROM test_table;

INSERT INTO test_table VALUES (2, 'Lettuce', 2.92);
> ERROR:  permission denied for relation test_table

```

#### Cleaning up credentials

We can use `vault lease revoke` to send an asynchronous revocation request before the TTL expires:

```bash
vault lease revoke database/creds/dev-read/TLCjNu5vT73r0QCW6X86f26Z
All revocation operations queued successfully!
```

Always ensure it actually gets revoked:

```bash
# docker-compose logs
vault_1     | [INFO]  expiration: revoked lease: lease_id=database/creds/dev-read/TLCjNu5vT73r0QCW6X86f26Z

# PSQL \du; command:
psql -h localhost -U postgres -W -d postgres -c "\du;"
```

If you actually attempt to revoke the `service-write` user, it won't let you as its the owner of the 
`test_table` relation, even if `vault lease revoke` won't directly return an error: 

```bash
vault lease revoke database/creds/service-write/lVpzrysA5akqSvjZVtCgx1i9
All revocation operations queued successfully!

# Errors seen in the docker-compose logs:
vault_1     | [ERROR] expiration: failed to revoke lease: 
lease_id=database/creds/service-write/lVpzrysA5akqSvjZVtCgx1i9 error="failed to revoke entry: resp: (*logical.Response)(nil) err: pq: cannot be dropped because some objects depend on it"
```

In order for this revocation to succeed, you'd need to `DROP` the `test_table` first:

```bash
psql -h localhost -U postgres -W -d postgres -c "DROP TABLE test_table;"
DROP TABLE

# Revocation working now:
vault lease revoke database/creds/service-write/lVpzrysA5akqSvjZVtCgx1i9
All revocation operations queued successfully!

vault_1     | [INFO]  expiration: revoked lease: lease_id=database/creds/service-write/lVpzrysA5akqSvjZVtCgx1i9
```

That's why it's a good idea to use PostgreSQL role inheritance to avoid objects being owned by individual 
users and using shared roles instead. Further reading [here](https://www.postgresql.org/docs/9.0/role-membership.html).

### Cleaning up the infrastructure

Just run `terraform destroy` and `docker-compose rm`. If there are any leases pending, Vault will try to 
revoke them first so keep in mind the Postgres object ownership point above.
