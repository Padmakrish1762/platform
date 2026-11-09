provider "keycloak" {
  client_id     = "admin-cli"
  realm         = "master"
  username      = var.username
  password      = var.password
  url           = var.root_url
}
