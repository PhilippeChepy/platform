resource "vault_mount" "kv_backup" {
  path        = "kv/platform/backup"
  description = "Platform backup Secrets"

  type = "kv"
}

resource "vault_mount" "secret_exoscale" {
  path        = "kv/platform/exoscale"
  description = "Exoscale Secrets"

  type = "kv"
}

// Authentication role

resource "vault_generic_endpoint" "auth_exoscale_role_vault_server" {
  path         = "auth/exoscale/role/vault-server"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      local.cluster_name,
    ]
    validator = "client_ip == instance_public_ip && \"${var.specs.infrastructure.name}-vault-cluster\" in instance_security_group_names"
  })
}

// Auto discovery

resource "exoscale_iam_access_key" "instance_pool_access_key" {
  name = "${var.specs.infrastructure.name}-vault-instance-pool"

  operations = [
    "list-instance-pools",
    "get-anti-affinity-group",
    "get-security-group",
    "get-instance-pool",
    "get-elastic-ip",
    "get-instance",
    "get-instance-type",
    "get-reverse-dns-instance",
    "get-template",
    "list-instances",
  ]
}

resource "vault_generic_secret" "instance_pool_access_key" {
  path = "kv/platform/exoscale/vault-instance-pool"

  data_json = jsonencode({
    api_key    = exoscale_iam_access_key.instance_pool_access_key.key
    api_secret = exoscale_iam_access_key.instance_pool_access_key.secret
  })
}

// Vault Backups

resource "exoscale_iam_access_key" "backup_access_key" {
  name = "${var.specs.infrastructure.name}-vault-backup"

  operations = [
    "list-sos-bucket",
    "put-sos-object",
    "get-sos-object",
    "delete-sos-object"
  ]

  resources = ["sos/bucket:${var.specs.backup.prefix}-${local.cluster_name}.${var.specs.backup.zone}"]
}

resource "vault_generic_secret" "backup_access_key" {
  path = "${vault_mount.secret_exoscale.path}/vault-backup"

  data_json = jsonencode({
    api_key    = exoscale_iam_access_key.backup_access_key.key
    api_secret = exoscale_iam_access_key.backup_access_key.secret
  })
}

resource "tls_private_key" "backup_keypair" {
  algorithm   = upper(var.specs.backup.encryption.algorithm)
  ecdsa_curve = try(var.specs.backup.encryption.ecdsa_curve, null)
  rsa_bits    = try(var.specs.backup.encryption.rsa_bits, null)
}

resource "vault_generic_secret" "backup_public" {
  path = "kv/platform/backup/vault-public"

  data_json = jsonencode({
    key = tls_private_key.backup_keypair.public_key_pem
  })
}

resource "vault_generic_secret" "backup_private" {
  path = "kv/platform/backup/vault-private"

  data_json = jsonencode({
    key = tls_private_key.backup_keypair.private_key_pem
  })
}

// Root CA

resource "vault_mount" "pki_root" {
  path        = "pki/root"
  description = "Platform CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.root.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.root.ttl_hours * 3600
}

resource "vault_pki_secret_backend_config_ca" "pki_root" {
  depends_on = [vault_mount.pki_root]
  backend    = vault_mount.pki_root.path

  pem_bundle = var.root_ca_bundle
}

resource "vault_pki_secret_backend_config_urls" "pki_root" {
  depends_on           = [vault_mount.pki_root]
  backend              = vault_mount.pki_root.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_root.path}/ca"]
}

// Vault ICA

resource "vault_mount" "pki_vault" {
  path        = "pki/platform/vault"
  description = "Vault ICA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.vault.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.vault.ttl_hours * 3600
}

resource "vault_pki_secret_backend_intermediate_cert_request" "pki_vault" {
  depends_on = [vault_mount.pki_vault]
  backend    = vault_mount.pki_vault.path
  type       = "internal"
  key_type   = lower(var.specs.pki.vault.algorithm)
  key_bits   = var.specs.pki.vault.rsa_bits

  common_name    = var.specs.pki.vault.common_name
  ou             = try(var.specs.pki.vault.subject.organizational_unit, null)
  organization   = try(var.specs.pki.vault.subject.organization, null)
  street_address = try(join("-", var.specs.pki.vault.subject.street_address), null)
  postal_code    = try(var.specs.pki.vault.subject.postal_code, null)
  locality       = try(var.specs.pki.vault.subject.locality, null)
  province       = try(var.specs.pki.vault.subject.province, null)
  country        = try(var.specs.pki.vault.subject.country, null)
}

resource "vault_pki_secret_backend_root_sign_intermediate" "pki_vault" {
  depends_on = [
    vault_pki_secret_backend_intermediate_cert_request.pki_vault,
    vault_pki_secret_backend_config_ca.pki_root
  ]
  backend = vault_mount.pki_root.path

  csr = vault_pki_secret_backend_intermediate_cert_request.pki_vault.csr
  ttl = var.specs.pki.vault.ttl_hours * 3600

  common_name    = var.specs.pki.vault.common_name
  ou             = try(var.specs.pki.vault.subject.organizational_unit, null)
  organization   = try(var.specs.pki.vault.subject.organization, null)
  street_address = try(join("-", var.specs.pki.vault.subject.street_address), null)
  postal_code    = try(var.specs.pki.vault.subject.postal_code, null)
  locality       = try(var.specs.pki.vault.subject.locality, null)
  province       = try(var.specs.pki.vault.subject.province, null)
  country        = try(var.specs.pki.vault.subject.country, null)
}

resource "vault_pki_secret_backend_intermediate_set_signed" "pki_vault" {
  backend = vault_mount.pki_vault.path

  certificate = vault_pki_secret_backend_root_sign_intermediate.pki_vault.certificate
}

resource "vault_pki_secret_backend_config_urls" "pki_vault" {
  depends_on           = [vault_mount.pki_vault]
  backend              = vault_mount.pki_vault.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_vault.path}/ca"]
}

// Vault server role

resource "vault_pki_secret_backend_role" "pki_vault" {
  depends_on = [vault_mount.pki_vault]

  backend            = vault_mount.pki_vault.path
  name               = "server"
  ttl                = var.specs.pki.vault.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.vault.algorithm)
  key_bits           = var.specs.pki.vault.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  server_flag        = true
  client_flag        = false

  ou             = ["vault"]
  organization   = split(",", try(var.specs.pki.vault.subject.organization, null))
  street_address = split(",", try(join("-", var.specs.pki.vault.subject.street_address), null))
  postal_code    = split(",", try(var.specs.pki.vault.subject.postal_code, null))
  locality       = split(",", try(var.specs.pki.vault.subject.locality, null))
  province       = split(",", try(var.specs.pki.vault.subject.province, null))
  country        = split(",", try(var.specs.pki.vault.subject.country, null))
}

// Vault server policy

// TODO: move vault stuff to specific kv engine (e.g.: move kv/platform/exoscale/vault* & kv/platform/backup/vault* to kv/platform/etcd/backup/*)

resource "vault_policy" "vault_server" {
  name = local.cluster_name

  policy = <<EOT
path "${vault_mount.pki_vault.path}/issue/server" {
  capabilities = ["create", "update"]
}

path "${vault_mount.secret_exoscale.path}/vault-backup" {
  capabilities = ["read"]
}

path "${vault_generic_secret.backup_public.path}" {
  capabilities = ["read"]
}

# Raft snapshots
path "sys/storage/raft/snapshot"
{
  capabilities = ["read"]
}
EOT
}
