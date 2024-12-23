resource "dns_a_record_set" "vault" {
  zone = "home.devnexuslab.me"
  name = "vault"
  addresses = ["192.168.1.106"]
  ttl = 300
}

