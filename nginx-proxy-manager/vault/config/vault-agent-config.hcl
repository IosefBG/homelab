pid_file = "/vault/vault-agent.pid"

vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path = "/vault/config/role_id"
      secret_id_file_path = "/vault/config/secret_id"
    }
  }
}

template {
  source      = "/vault/config/templates/db_host.tpl"
  destination = "/vault/secrets/db_host"
}

template {
  source      = "/vault/config/templates/db_port.tpl"
  destination = "/vault/secrets/db_port"
}

template {
  source      = "/vault/config/templates/db_user.tpl"
  destination = "/vault/secrets/db_user"
}

template {
  source      = "/vault/config/templates/db_password.tpl"
  destination = "/vault/secrets/db_password"
}

template {
  source      = "/vault/config/templates/db_name.tpl"
  destination = "/vault/secrets/db_name"
}