resource "keycloak_openid_client" "clients" {
  for_each          = local.clients
  realm_id          = keycloak_realm.my_realm.id
  client_id         = each.value.client_id
  enabled           = true
  access_type       = "CONFIDENTIAL"
  client_authenticator_type     = "client-secret"
  standard_flow_enabled         = each.value.client_id == "trust-client" ? false : true
  direct_access_grants_enabled  = each.value.client_id == "trust-client" ? false : true
  service_accounts_enabled      = true
  valid_redirect_uris           = each.value.client_id == "trust-client" ? [] : [var.redirect_url]
  root_url                      = each.value.client_id == "trust-client" ? "" : var.root_url
  web_origins                   = each.value.client_id == "trust-client" ? [] : [var.root_url]
}

# Data source to fetch the realm-management client
data "keycloak_openid_client" "realm_management_client" {
  realm_id  = keycloak_realm.my_realm.id
  client_id = "realm-management"
}

resource "keycloak_openid_client_service_account_role" "create_client_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "create-client"
}

resource "keycloak_openid_client_service_account_role" "manage_clients_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "manage-clients"
}

resource "keycloak_openid_client_service_account_role" "query_clients_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "query-clients"
}

resource "keycloak_openid_client_service_account_role" "view_clients_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "view-clients"
}

resource "keycloak_openid_client_service_account_role" "manage_users_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "manage-users"
}

resource "keycloak_openid_client_service_account_role" "query_users_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "query-users"
}

resource "keycloak_openid_client_service_account_role" "view_users_role" {
  for_each                = { for k, v in local.clients : k => v if v.client_id != "trust-client" }
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients[each.key].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "view-users"
}
resource "keycloak_openid_client_service_account_role" "manage_realm_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients["client2"].service_account_user_id
  client_id               = data.keycloak_openid_client.realm_management_client.id
  role                    = "manage-realm"
}

# Assign trust-client-role to trust-client service account
resource "keycloak_openid_client_service_account_realm_role" "trust_client_realm_role" {
  realm_id                = keycloak_realm.my_realm.id
  service_account_user_id = keycloak_openid_client.clients["client3"].service_account_user_id
  role                    = keycloak_role.trust_client_role.name
}