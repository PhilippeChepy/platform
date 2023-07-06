// Authentication role

resource "vault_generic_endpoint" "auth_exoscale_role_etcd_server" {
  path         = "auth/exoscale/role/etcd-server"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      local.cluster_name,
    ]
    validator = "client_ip == instance_public_ip && \"${var.specs.infrastructure.name}-etcd-cluster\" in instance_security_group_names"
  })
}

// Auto discovery

resource "exoscale_iam_access_key" "instance_pool_access_key" {
  name = "${var.specs.infrastructure.name}-etcd-instance-pool"

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
  path = "kv/platform/exoscale/etcd-instance-pool"

  data_json = jsonencode({
    api_key    = exoscale_iam_access_key.instance_pool_access_key.key
    api_secret = exoscale_iam_access_key.instance_pool_access_key.secret
  })
}

// Etcd Backups

resource "exoscale_iam_access_key" "backup_access_key" {
  name = "${var.specs.infrastructure.name}-etcd-backup"

  operations = [
    "list-sos-bucket",
    "put-sos-object",
    "get-sos-object",
    "delete-sos-object"
  ]

  resources = ["sos/bucket:${var.specs.backup.prefix}-${local.cluster_name}.${var.specs.backup.zone}"]
}

resource "vault_generic_secret" "backup_access_key" {
  path = "kv/platform/exoscale/etcd-backup"

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
  path = "kv/platform/backup/etcd-public"

  data_json = jsonencode({
    key = tls_private_key.backup_keypair.public_key_pem
  })
}

resource "vault_generic_secret" "backup_private" {
  path = "kv/platform/backup/etcd-private"

  data_json = jsonencode({
    key = tls_private_key.backup_keypair.private_key_pem
  })
}

// Etcd CA

resource "vault_mount" "pki_etcd" {
  path        = "pki/platform/kubernetes/etcd"
  description = "Etcd CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.etcd.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.etcd.ttl_hours * 3600
}

resource "vault_pki_secret_backend_root_cert" "pki_etcd" {
  depends_on = [vault_mount.pki_etcd]

  backend  = vault_mount.pki_etcd.path
  type     = "internal"
  key_type = lower(var.specs.pki.etcd.algorithm)
  key_bits = var.specs.pki.etcd.rsa_bits
  ttl      = var.specs.pki.etcd.ttl_hours * 3600

  common_name    = var.specs.pki.etcd.common_name
  ou             = try(var.specs.pki.etcd.subject.organizational_unit, null)
  organization   = try(var.specs.pki.etcd.subject.organization, null)
  street_address = try(join("-", var.specs.pki.etcd.subject.street_address), null)
  postal_code    = try(var.specs.pki.etcd.subject.postal_code, null)
  locality       = try(var.specs.pki.etcd.subject.locality, null)
  province       = try(var.specs.pki.etcd.subject.province, null)
  country        = try(var.specs.pki.etcd.subject.country, null)
}

resource "vault_pki_secret_backend_config_urls" "pki_etcd" {
  depends_on = [vault_mount.pki_etcd]

  backend              = vault_mount.pki_etcd.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_etcd.path}/ca"]
}

// Roles

resource "vault_pki_secret_backend_role" "pki_etcd" {
  depends_on = [vault_mount.pki_etcd]

  backend            = vault_mount.pki_etcd.path
  name               = "server"
  ttl                = var.specs.pki.etcd.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.etcd.algorithm)
  key_bits           = var.specs.pki.etcd.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  enforce_hostnames  = false
  server_flag        = true
  client_flag        = true

  ou             = split(",", try(var.specs.pki.etcd.subject.organizational_unit, null))
  organization   = split(",", try(var.specs.pki.etcd.subject.organization, null))
  street_address = split(",", try(join("-", var.specs.pki.etcd.subject.street_address), null))
  postal_code    = split(",", try(var.specs.pki.etcd.subject.postal_code, null))
  locality       = split(",", try(var.specs.pki.etcd.subject.locality, null))
  province       = split(",", try(var.specs.pki.etcd.subject.province, null))
  country        = split(",", try(var.specs.pki.etcd.subject.country, null))
}

// Policies

// TODO: move etcd stuff to specific kv engine (e.g.: move kv/platform/exoscale/etcd* & kv/platform/backup/etcd* to kv/platform/etcd/backup/*)

resource "vault_policy" "etcd_server" {
  name = local.cluster_name

  policy = <<EOT
path "${vault_mount.pki_etcd.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_etcd.path}/issue/server" {
  capabilities = ["create", "update"]
}

path "kv/platform/exoscale/etcd-instance-pool" {
  capabilities = ["read"]
}

path "kv/platform/exoscale/etcd-backup" {
  capabilities = ["read"]
}

path "kv/platform/backup/etcd-public" {
  capabilities = ["read"]
}
EOT
}
