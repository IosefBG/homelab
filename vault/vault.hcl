storage "postgresql" {
  connection_url = "postgresql://vault_user:vault_password@db:5432/vault?sslmode=disable"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1  # Disable TLS for initial setup
}

disable_mlock = true
ui = true