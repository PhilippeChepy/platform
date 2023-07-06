// Exoscale authentication plugin

resource "exoscale_iam_access_key" "access_key" {
  name = "${var.specs.infrastructure.name}-vault-plugin-exoscale-authentication"

  operations = [
    "list-zones",
    "list-instances",
    "list-security-groups",
    "get-instance",
    "get-instance-pool",
    "get-security-group"
  ]
}

resource "vault_generic_endpoint" "exoscale_auth_plugin_register" {
  path         = "sys/plugins/catalog/auth/exoscale"
  disable_read = true
  data_json = jsonencode({
    args    = ["-ca-cert=/var/vault/tls/server.pem"]
    builtin = false
    command = "vault-plugin-auth-exoscale"
    name    = "exoscale"
    sha256  = var.exoscale_auth_plugin_hash
  })
}

resource "vault_auth_backend" "auth_exoscale" {
  depends_on = [vault_generic_endpoint.exoscale_auth_plugin_register]
  type       = "exoscale"
}

resource "vault_generic_endpoint" "auth_exoscale_config" {
  depends_on     = [vault_auth_backend.auth_exoscale]
  path           = "auth/exoscale/config"
  disable_delete = true
  data_json = jsonencode({
    api_environment = "api"
    api_key         = exoscale_iam_access_key.access_key.key
    api_secret      = exoscale_iam_access_key.access_key.secret
    approle_mode    = true,
    zone            = var.specs.infrastructure.zone
  })
}