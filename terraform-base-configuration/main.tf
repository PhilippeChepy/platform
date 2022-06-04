# Exoscale plugin: secret engine

resource "vault_generic_endpoint" "exoscale_secret_plugin_register" {
  path         = "sys/plugins/catalog/secret/exoscale"
  disable_read = true
  data_json = jsonencode({
    name    = "exoscale"
    command = "vault-plugin-secrets-exoscale"
    args    = ["-ca-cert=/etc/vault/tls/server.pem"]
    sha256  = var.exoscale_secret_plugin_hash
  })
}

resource "vault_mount" "iam_exoscale" {
  depends_on  = [vault_generic_endpoint.exoscale_secret_plugin_register]
  path        = "iam/exoscale"
  type        = "exoscale"
  description = "Exoscale IAM"
}

resource "vault_generic_endpoint" "iam_exoscale_config_root" {
  depends_on     = [vault_mount.iam_exoscale]
  path           = "${vault_mount.iam_exoscale.path}/config/root"
  disable_delete = true
  data_json = jsonencode({
    api_environment = "api"
    root_api_key    = local.platform_exoscale_credentials.key,
    root_api_secret = local.platform_exoscale_credentials.secret,
    zone            = local.platform_zone
  })
}

resource "vault_generic_endpoint" "iam_exoscale_config_lease" {
  depends_on   = [vault_mount.iam_exoscale]
  path         = "${vault_mount.iam_exoscale.path}/config/lease"
  disable_read = true
  data_json = jsonencode({
    ttl     = "24h",
    max_ttl = "48h"
  })
}

resource "vault_generic_endpoint" "iam_exoscale_role_etcd_instance_pool" {
  depends_on   = [vault_mount.iam_exoscale]
  path         = "${vault_mount.iam_exoscale.path}/role/etcd-instance-pool"
  disable_read = true
  data_json = jsonencode({
    operations = []
  })
}

resource "vault_generic_endpoint" "iam_exoscale_role_cloud_controller_manager" {
  depends_on   = [vault_mount.iam_exoscale]
  path         = "${vault_mount.iam_exoscale.path}/role/cloud-controller-manager"
  disable_read = true
  data_json = jsonencode({
    operations = []
  })
}

resource "vault_generic_endpoint" "iam_exoscale_role_cluster_autoscaler" {
  depends_on   = [vault_mount.iam_exoscale]
  path         = "${vault_mount.iam_exoscale.path}/role/cluster-autoscaler"
  disable_read = true
  data_json = jsonencode({
    operations = []
  })
}

# Root CA: only used through Terraform to sign and setup ICAs

resource "vault_mount" "pki_root" {
  path        = "pki/root"
  description = "Platform CA"

  type                      = "pki"
  default_lease_ttl_seconds = local.platform_default_tls_ttl.ca * 3600
  max_lease_ttl_seconds     = local.platform_default_tls_ttl.ca * 3600
}

resource "vault_pki_secret_backend_config_ca" "pki_root" {
  depends_on = [vault_mount.pki_root]
  backend    = vault_mount.pki_root.path

  pem_bundle = "${data.local_sensitive_file.root_ca_private_key_pem.content}${data.local_file.root_ca_certificate_pem.content}"
}

resource "vault_pki_secret_backend_config_urls" "pki_root" {
  depends_on           = [vault_mount.pki_root]
  backend              = vault_mount.pki_root.path
  issuing_certificates = ["https://${local.platform_components.vault.endpoint}/v1/${vault_mount.pki_root.path}/ca"]
}

# Vault

resource "vault_mount" "pki_vault" {
  path        = "pki/platform/vault"
  description = "Vault ICA"

  type                      = "pki"
  default_lease_ttl_seconds = local.platform_default_tls_ttl.ica * 3600
  max_lease_ttl_seconds     = local.platform_default_tls_ttl.ica * 3600
}

resource "vault_pki_secret_backend_intermediate_cert_request" "pki_vault" {
  depends_on = [vault_mount.pki_vault]
  backend    = vault_mount.pki_vault.path
  type       = "internal"
  key_type   = lower(local.platform_default_tls_algorithm.algorithm)
  key_bits   = local.platform_default_tls_algorithm.rsa_bits

  common_name    = "Vault ICA"
  ou             = try(local.platform_default_tls_subject.organizational_unit, null)
  organization   = try(local.platform_default_tls_subject.organization, null)
  street_address = try(join("-", local.platform_default_tls_subject.street_address), null)
  postal_code    = try(local.platform_default_tls_subject.postal_code, null)
  locality       = try(local.platform_default_tls_subject.locality, null)
  province       = try(local.platform_default_tls_subject.province, null)
  country        = try(local.platform_default_tls_subject.country, null)
}

resource "vault_pki_secret_backend_root_sign_intermediate" "pki_vault" {
  depends_on = [
    vault_pki_secret_backend_intermediate_cert_request.pki_vault,
    vault_pki_secret_backend_config_ca.pki_root
  ]
  backend = vault_mount.pki_root.path

  csr = vault_pki_secret_backend_intermediate_cert_request.pki_vault.csr
  ttl = local.platform_default_tls_ttl.ica * 3600

  common_name    = "Vault ICA"
  ou             = try(local.platform_default_tls_subject.organizational_unit, null)
  organization   = try(local.platform_default_tls_subject.organization, null)
  street_address = try(join("-", local.platform_default_tls_subject.street_address), null)
  postal_code    = try(local.platform_default_tls_subject.postal_code, null)
  locality       = try(local.platform_default_tls_subject.locality, null)
  province       = try(local.platform_default_tls_subject.province, null)
  country        = try(local.platform_default_tls_subject.country, null)
}

resource "vault_pki_secret_backend_intermediate_set_signed" "pki_vault" {
  backend = vault_mount.pki_vault.path

  certificate = <<-EOT
  ${vault_pki_secret_backend_root_sign_intermediate.pki_vault.certificate}
  ${vault_pki_secret_backend_root_sign_intermediate.pki_vault.issuing_ca}
  EOT
}

resource "vault_pki_secret_backend_config_urls" "pki_vault" {
  depends_on           = [vault_mount.pki_vault]
  backend              = vault_mount.pki_vault.path
  issuing_certificates = ["https://${local.platform_components.vault.endpoint}/v1/${vault_mount.pki_vault.path}/ca"]
}

## Vault roles

resource "vault_pki_secret_backend_role" "pki_vault" {
  depends_on = [vault_mount.pki_vault]
  for_each = {
    "vault-server" = { name = "server", server_flag = true, client_flag = false }
  }

  backend            = vault_mount.pki_vault.path
  name               = try(each.value.name, each.key)
  ttl                = local.platform_default_tls_ttl.cert * 3600
  key_type           = lower(local.platform_default_tls_algorithm.algorithm)
  key_bits           = local.platform_default_tls_algorithm.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou             = ["vault"]
  organization   = try([local.platform_default_tls_subject.organization], null)
  street_address = try([join("-", local.platform_default_tls_subject.street_address)], null)
  postal_code    = try([local.platform_default_tls_subject.postal_code], null)
  locality       = try([local.platform_default_tls_subject.locality], null)
  province       = try([local.platform_default_tls_subject.province], null)
  country        = try([local.platform_default_tls_subject.country], null)
}

## Vault policy

resource "vault_policy" "vault_server" {
  name = "platform-vault-server"

  policy = <<EOT
path "${vault_mount.pki_vault.path}/issue/server" {
  capabilities = ["create", "update"]
}
EOT
}

# Kubernetes

resource "random_string" "token_id" {
  length  = 6
  lower   = true
  number  = true
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  lower   = true
  number  = true
  special = false
  upper   = false
}

module "kubelet_ca_certificate" {
  source = "git@github.com:PhilippeChepy/terraform-tls-root-ca.git"

  key_algorithm = local.platform_default_tls_algorithm.algorithm
  ecdsa_curve   = try(local.platform_default_tls_algorithm.ecdsa_curve, null)
  rsa_bits      = try(local.platform_default_tls_algorithm.rsa_bits, null)

  subject = merge(
    { common_name = "Kubernetes Kubelets CA" },
    local.platform_default_tls_subject
  )
  validity_period_hours = local.platform_default_tls_ttl.ca
}

resource "vault_mount" "pki_kubernetes" {
  for_each = {
    etcd              = { description = "Kubernetes Store (etcd) CA " }
    control-plane     = { description = "Kubernetes Control-Plane CA" }
    kubelet           = { description = "Kubernetes Kubelets CA" }
    aggregation-layer = { description = "Kubernetes Aggregation-Layer CA" }
    client            = { description = "Kubernetes Clients CA" }
  }

  path        = "pki/platform/kubernetes/${each.key}"
  description = each.value.description

  type                      = "pki"
  default_lease_ttl_seconds = local.platform_default_tls_ttl.ca * 3600
  max_lease_ttl_seconds     = local.platform_default_tls_ttl.ca * 3600
}

resource "vault_pki_secret_backend_root_cert" "pki_kubernetes" {
  depends_on = [vault_mount.pki_kubernetes]
  for_each   = { for layer, definition in vault_mount.pki_kubernetes : layer => definition if layer != "kubelet" }

  backend  = vault_mount.pki_kubernetes[each.key].path
  type     = "internal"
  key_type = lower(local.platform_default_tls_algorithm.algorithm)
  key_bits = local.platform_default_tls_algorithm.rsa_bits
  ttl      = local.platform_default_tls_ttl.ca * 3600

  common_name    = each.value.description
  ou             = try(local.platform_default_tls_subject.organizational_unit, null)
  organization   = try(local.platform_default_tls_subject.organization, null)
  street_address = try(join("-", local.platform_default_tls_subject.street_address), null)
  postal_code    = try(local.platform_default_tls_subject.postal_code, null)
  locality       = try(local.platform_default_tls_subject.locality, null)
  province       = try(local.platform_default_tls_subject.province, null)
  country        = try(local.platform_default_tls_subject.country, null)
}

resource "vault_pki_secret_backend_config_ca" "pki_kubernetes_kubelet" {
  depends_on = [vault_mount.pki_kubernetes]
  backend    = vault_mount.pki_kubernetes["kubelet"].path

  pem_bundle = "${module.kubelet_ca_certificate.private_key_pem}${module.kubelet_ca_certificate.certificate_pem}"
}

resource "vault_pki_secret_backend_config_urls" "pki_kubernetes" {
  depends_on = [vault_mount.pki_kubernetes]
  for_each   = vault_mount.pki_kubernetes

  backend              = vault_mount.pki_kubernetes[each.key].path
  issuing_certificates = ["https://${local.platform_components.vault.endpoint}/v1/${vault_mount.pki_kubernetes[each.key].path}/ca"]
}

resource "vault_mount" "secret_kubernetes" {
  path        = "kv/platform/kubernetes"
  description = "Kubernetes Secrets"

  type                      = "kv"
  default_lease_ttl_seconds = local.platform_default_tls_ttl.cert * 3600
  max_lease_ttl_seconds     = local.platform_default_tls_ttl.cert * 3600
}

resource "tls_private_key" "service_account" {
  algorithm   = local.platform_default_tls_algorithm.algorithm
  ecdsa_curve = try(local.platform_default_tls_algorithm.ecdsa_curve, null)
  rsa_bits    = try(local.platform_default_tls_algorithm.rsa_bits, null)
}

resource "random_password" "default_encryption_key" {
  for_each = toset([for key_index in range(1) : "key-${key_index}"])

  length  = 32
  special = true
}

resource "vault_generic_secret" "secret_service_account_keypair" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/service-account"

  data_json = jsonencode({
    private_key = tls_private_key.service_account.private_key_pem,
    public_key  = tls_private_key.service_account.public_key_pem
  })
}

resource "vault_generic_secret" "secret_encryption_keys" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/secret-encryption"

  data_json = jsonencode({
    keys = { for key_name, encryption_key in random_password.default_encryption_key : key_name => encryption_key.result }
  })
}

resource "vault_generic_secret" "kubelet_pki" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/kubelet-pki"

  data_json = jsonencode({
    private_key = module.kubelet_ca_certificate.private_key_pem
    certificate = module.kubelet_ca_certificate.certificate_pem
  })
}

resource "vault_generic_secret" "kubelet_bootstrap_token" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/kubelet-bootstrap-token"

  data_json = jsonencode({
    id     = random_string.token_id.result
    secret = random_string.token_secret.result
  })
}

## Roles

resource "vault_pki_secret_backend_role" "pki_kubernetes" {
  depends_on = [vault_mount.pki_kubernetes]
  for_each = {
    "etcd" = {
      name        = "server"
      backend     = "etcd"
      server_flag = true
      client_flag = true
    }
    "etcd--apiserver" = {
      name        = "apiserver"
      backend     = "etcd"
      server_flag = false
      client_flag = true
    }
    "apiserver" = {
      backend         = "control-plane"
      allowed_domains = [local.platform_components.kubernetes.endpoint, "kubernetes", "kubernetes.default", "kubernetes.default.svc", /* TODO: remove "kubernetes.default.svc.cluster",*/ "kubernetes.default.svc.${local.platform_components.kubernetes.cluster_domain}"]
      server_flag     = true
      client_flag     = false
    }
    "apiserver--controller-manager" = { # kubeconfig
      name            = "controller-manager"
      backend         = "control-plane"
      allowed_domains = ["system:kube-controller-manager"]
      organization    = "system:kube-controller-manager"
      server_flag     = false,
      client_flag     = true
    }
    "apiserver--scheduler" = { # kubeconfig
      name            = "scheduler"
      backend         = "control-plane"
      allowed_domains = ["system:kube-scheduler"]
      organization    = "system:kube-scheduler"
      server_flag     = false,
      client_flag     = true
    }
    "apiserver--exoscale-cloud-controller-manager" = { # kubeconfig
      name            = "cloud-controller-manager"
      backend         = "control-plane"
      allowed_domains = ["exoscale-cloud-controller-manager"]
      server_flag     = false,
      client_flag     = true
    }
    "apiserver--konnectivity" = { # kubeconfig
      name            = "konnectivity"
      backend         = "control-plane"
      allowed_domains = ["system:konnectivity-server"]
      organization    = "system:kube-konnectivity-server"
      server_flag     = false
      client_flag     = true
    }
    "konnectivity--apiserver" = {
      name            = "konnectivity-apiserver-egress"
      backend         = "control-plane"
      allowed_domains = ["kube-apiserver-konnectivity-client"]
      organization    = "system:masters"
      server_flag     = false
      client_flag     = true
    }
    "konnectivity-server-apiserver" = {
      name            = "konnectivity-server-apiserver"
      backend         = "control-plane"
      allowed_domains = ["konnectivity"]
      organization    = "konnectivity"
      server_flag     = true,
      client_flag     = false
    }
    "konnectivity-server-cluster" = {
      name            = "konnectivity-server-cluster"
      backend         = "control-plane"
      allowed_domains = ["konnectivity"]
      organization    = "konnectivity"
      server_flag     = true,
      client_flag     = false
    }
    "konnectivity-agent" = {
      name            = "konnectivity-agent"
      backend         = "control-plane"
      allowed_domains = ["konnectivity"]
      organization    = "konnectivity"
      server_flag     = true,
      client_flag     = false
    }
    "aggregation-layer--metrics-server" = {
      name        = "metrics-server"
      backend     = "aggregation-layer"
      server_flag = true,
      client_flag = false
    }
    "aggregation-layer--apiserver" = {
      name        = "apiserver"
      backend     = "aggregation-layer"
      server_flag = false,
      client_flag = true
    }
    "kubelet--apiserver" = {
      name         = "apiserver"
      backend      = "kubelet"
      organization = "system:masters"
      server_flag  = false,
      client_flag  = true
    }
    "client--operator-admin" = {
      name            = "operator-admin"
      backend         = "client",
      allowed_domains = ["cluster-admin"]
      organization    = "system:masters"
      server_flag     = false
      client_flag     = true
    }
  }

  backend            = vault_mount.pki_kubernetes[each.value.backend].path
  name               = try(each.value.name, each.key)
  ttl                = local.platform_default_tls_ttl.cert * 3600
  key_type           = lower(local.platform_default_tls_algorithm.algorithm)
  key_bits           = local.platform_default_tls_algorithm.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  allowed_domains    = try(each.value.allowed_domains, null)
  enforce_hostnames  = false
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou             = ["kubernetes"]
  organization   = try([each.value.organization], [local.platform_default_tls_subject.organization], null)
  street_address = try([join("-", local.platform_default_tls_subject.street_address)], null)
  postal_code    = try([local.platform_default_tls_subject.postal_code], null)
  locality       = try([local.platform_default_tls_subject.locality], null)
  province       = try([local.platform_default_tls_subject.province], null)
  country        = try([local.platform_default_tls_subject.country], null)
}

## Policies

resource "vault_policy" "etcd_server" {
  name = "platform-kubernetes-etcd"

  policy = <<EOT
path "${vault_mount.pki_kubernetes["etcd"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["etcd"].path}/issue/server" {
  capabilities = ["create", "update"]
}

path "${vault_mount.iam_exoscale.path}/apikey/etcd-instance-pool" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "kubernetes_control_plane" {
  name = "platform-kubernetes-control-plane"

  policy = <<EOT
## API server
path "${vault_mount.pki_kubernetes["etcd"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["etcd"].path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["client"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/konnectivity-apiserver-egress" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["aggregation-layer"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["aggregation-layer"].path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["kubelet"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["kubelet"].path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_generic_secret.secret_service_account_keypair.path}" {
  capabilities = ["read"]
}

path "${vault_generic_secret.secret_encryption_keys.path}" {
  capabilities = ["read"]
}

## Controller manager

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/controller-manager" {
  capabilities = ["create", "update"]
}

path "${vault_generic_secret.kubelet_pki.path}" {
  capabilities = ["read"]
}

# + path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_kubernetes["aggregation-layer"].path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_kubernetes["kubelet"].path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_generic_secret.secret_service_account_keypair.path}" { capabilities = ["read"] }

## Scheduler

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/scheduler" {
  capabilities = ["create", "update"]
}

# + path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_kubernetes["kubelet"].path}/cert/ca_chain" { capabilities = ["read"] }

## Konnectivity (server)

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/konnectivity" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/konnectivity-server-apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/konnectivity-server-cluster" {
  capabilities = ["create", "update"]
}

# + path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" { capabilities = ["read"] }

## Exoscale cloud controller manager

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/cloud-controller-manager" {
  capabilities = ["create", "update"]
}

path "${vault_mount.iam_exoscale.path}/apikey/cloud-controller-manager" {
  capabilities = ["read"]
}

# + path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" { capabilities = ["read"] }

## Admin client

path "${vault_mount.pki_kubernetes["client"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["client"].path}/issue/operator-admin" {
  capabilities = ["create", "update"]
}
EOT
}

resource "vault_policy" "metrics-server" {
  name = "platform-kubernetes-metrics-server"

  policy = <<EOT
path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["aggregation-layer"].path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["aggregation-layer"].path}/sign/metrics-server" {
  capabilities = ["create", "update"]
}
EOT
}

resource "vault_policy" "cluster_autoscaler" {
  name = "platform-kubernetes-cluster-autoscaler"

  policy = <<EOT
## Cluster Autoscaler

path "${vault_mount.pki_kubernetes["control-plane"].path}/issue/cluster-autoscaler" {
  capabilities = ["create", "update"]
}

path "${vault_mount.iam_exoscale.path}/apikey/cluster-autoscaler" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubernetes["control-plane"].path}/cert/ca_chain" {
  capabilities = ["read"]
}
EOT
}

# Authentication Methods

## User / pass (WIP)

# resource "vault_auth_backend" "userpass" {
#   type = "userpass"

#   tune {
#     max_lease_ttl      = "86400s"
#     listing_visibility = "unauth"
#   }
# }

## Exoscale auth

resource "vault_generic_endpoint" "exoscale_auth_plugin_register" {
  path = "sys/plugins/catalog/auth/exoscale"
  data_json = jsonencode({
    name    = "exoscale"
    builtin = false
    command = "vault-plugin-auth-exoscale"
    args    = ["-ca-cert=/etc/vault/tls/server.pem"]
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
    api_key         = local.platform_exoscale_credentials.key,
    api_secret      = local.platform_exoscale_credentials.secret,
    approle_mode    = true,
    zone            = local.platform_zone
  })
}

resource "vault_generic_endpoint" "auth_exoscale_role_vault_server" {
  depends_on   = [vault_auth_backend.auth_exoscale]
  path         = "auth/exoscale/role/vault-server"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      vault_policy.vault_server.name,
    ]
    validator = "client_ip == instance_public_ip && \"${local.platform_name}-vault-server\" in instance_security_group_names"
  })
}

resource "vault_generic_endpoint" "auth_exoscale_role_etcd_server" {
  depends_on   = [vault_auth_backend.auth_exoscale]
  path         = "auth/exoscale/role/etcd-server"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      vault_policy.etcd_server.name,
    ]
    validator = "client_ip == instance_public_ip && \"${local.platform_name}-etcd-server\" in instance_security_group_names"
  })
}

resource "vault_generic_endpoint" "auth_exoscale_role_kubernetes_control_plane" {
  depends_on   = [vault_auth_backend.auth_exoscale]
  path         = "auth/exoscale/role/kubernetes-control-plane"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      vault_policy.kubernetes_control_plane.name,
    ]
    validator = "client_ip == instance_public_ip && \"${local.platform_name}-kubernetes-controllers\" in instance_security_group_names"
  })
}

# TODO: admin token

resource "local_file" "properties_vault" {
  content = jsonencode({
    pki_sign_aggregation_layer = "${vault_mount.pki_kubernetes["aggregation-layer"].path}/sign/metrics-server"
  })
  filename = "${path.module}/../artifacts/properties-vault-configuration.json"
}