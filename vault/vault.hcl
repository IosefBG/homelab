storage "postgresql" {
  connection_url = "postgresql://vault_user:vault_password@db:5432/vault?sslmode=disable"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/config/certs/vault-cert.pem"
  tls_key_file  = "/vault/config/certs/vault-key.pem"
}

api_addr = "https://vault.home.devnexuslab.me:8200"
cluster_addr = "https://vault.home.devnexuslab.me:8201"
