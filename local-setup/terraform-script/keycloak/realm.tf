resource "keycloak_realm" "my_realm" {
  realm   = var.realm
  enabled           = true
  revoke_refresh_token = true
  refresh_token_max_reuse = 10
  access_token_lifespan = var.access_token_lifespan
  sso_session_idle_timeout = var.sso_session_idle_timeout
}

resource "keycloak_role" "holder_role" {
  realm_id = keycloak_realm.my_realm.id
  name     = var.realm_role
}

resource "keycloak_role" "trust_client_role" {
  realm_id = keycloak_realm.my_realm.id
  name     = var.trust_client_role
}