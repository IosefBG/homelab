provider "docker" {}

resource "docker_network" "vault_net" {
  name = "vault_network"
}

resource "docker_service" "vault" {
  name = "vault"
  networks = [docker_network.vault_net.name]

  task_template {
    container_spec {
      image = "vault:1.14"
      env = [
        "VAULT_ADDR=https://vault.home.devnexuslab.me",
        "VAULT_DEV_ROOT_TOKEN_ID=root",
      ]
      mounts = [
        {
          target = "/vault/config"
          source = "./vault.hcl"
          type   = "bind"
        }
      ]
    }

    resources {
      limits {
        memory = "256m"
      }
    }
  }
}
