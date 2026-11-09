output "admin_client_secret" {
  value = keycloak_openid_client.clients["client1"].client_secret
  sensitive = true
}

output "platform_client_secret" {
  value = keycloak_openid_client.clients["client2"].client_secret
  sensitive = true
}

output "trust_client_secret" {
  value = keycloak_openid_client.clients["client3"].client_secret
  sensitive = true
}

resource "local_file" "env_file" {
  filename = "secret.env"
  content  = <<EOT
ADMIN_CLIENT_SECRET=${keycloak_openid_client.clients["client1"].client_secret}
CREDEBL_CLIENT_SECRET=${keycloak_openid_client.clients["client2"].client_secret}
TRUST_CLIENT_SECRET=${keycloak_openid_client.clients["client3"].client_secret}
EOT
}
