// Authentication role

resource "vault_generic_endpoint" "auth_exoscale_role_kubernetes_control_plane" {
  path         = "auth/exoscale/role/kubernetes-control-plane"
  disable_read = true
  data_json = jsonencode({
    token_policies = [
      "default",
      local.cluster_name,
    ]
    validator = "client_ip == instance_public_ip && \"${var.specs.infrastructure.name}-kubernetes-cluster\" in instance_security_group_names"
  })
}

// Generic secret backend

resource "vault_mount" "secret_kubernetes" {
  path        = "kv/platform/kubernetes"
  description = "Kubernetes Secrets"

  type = "kv"
}

// Etcd encryption Key

resource "random_password" "default_encryption_key" {
  for_each = toset([for key_index in range(1) : "key-${key_index}"])

  length  = 32
  special = true
}

resource "vault_generic_secret" "secret_encryption_keys" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/secret-encryption"

  data_json = jsonencode({
    keys = { for key_name, encryption_key in random_password.default_encryption_key : key_name => encryption_key.result }
  })
}

// Etcd PKI role

resource "vault_pki_secret_backend_role" "pki_etcd" {
  backend            = "pki/platform/kubernetes/etcd"
  name               = "apiserver"
  ttl                = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits           = var.specs.pki.kubernetes_apiserver.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  enforce_hostnames  = false
  server_flag        = false
  client_flag        = true
}

// API Server PKI

resource "vault_mount" "pki_control_plane" {
  path        = "pki/platform/kubernetes/control-plane"
  description = "Kubernetes Control-Plane CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600
}

resource "vault_pki_secret_backend_root_cert" "pki_control_plane" {
  depends_on = [vault_mount.pki_control_plane]

  backend  = vault_mount.pki_control_plane.path
  type     = "internal"
  key_type = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits = var.specs.pki.kubernetes_apiserver.rsa_bits
  ttl      = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600

  common_name    = var.specs.pki.kubernetes_apiserver.common_name
  ou             = try(var.specs.pki.kubernetes_apiserver.subject.organizational_unit, null)
  organization   = try(var.specs.pki.kubernetes_apiserver.subject.organization, null)
  street_address = try(join("-", var.specs.pki.kubernetes_apiserver.subject.street_address), null)
  postal_code    = try(var.specs.pki.kubernetes_apiserver.subject.postal_code, null)
  locality       = try(var.specs.pki.kubernetes_apiserver.subject.locality, null)
  province       = try(var.specs.pki.kubernetes_apiserver.subject.province, null)
  country        = try(var.specs.pki.kubernetes_apiserver.subject.country, null)
}

resource "vault_pki_secret_backend_config_urls" "pki_control_plane" {
  depends_on = [vault_mount.pki_control_plane]

  backend              = vault_mount.pki_control_plane.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_control_plane.path}/ca"]
}

resource "vault_pki_secret_backend_role" "pki_control_plane" {
  depends_on = [vault_mount.pki_control_plane]
  for_each = {
    "apiserver" = {
      backend         = "control-plane"
      allowed_domains = ["kubernetes", "kubernetes.default", "kubernetes.default.svc", "kubernetes.default.svc.${var.specs.kubernetes.domain}"]
      server_flag     = true
      client_flag     = false
    }
    "controller-manager" = { # kubeconfig
      backend         = "control-plane"
      allowed_domains = ["system:kube-controller-manager"]
      organization    = "system:kube-controller-manager"
      server_flag     = false,
      client_flag     = true
    }
    "scheduler" = { # kubeconfig
      backend         = "control-plane"
      allowed_domains = ["system:kube-scheduler"]
      organization    = "system:kube-scheduler"
      server_flag     = false,
      client_flag     = true
    }
    "cloud-controller-manager" = { # kubeconfig
      backend         = "control-plane"
      allowed_domains = ["exoscale-cloud-controller-manager"]
      server_flag     = false,
      client_flag     = true
    }
    "cluster-autoscaler" = { # kubeconfig
      backend         = "control-plane"
      allowed_domains = ["exoscale-cluster-autoscaler"]
      server_flag     = false,
      client_flag     = true
    }
    "konnectivity" = { # kubeconfig
      backend         = "control-plane"
      allowed_domains = ["system:konnectivity-server"]
      organization    = "system:kube-konnectivity-server"
      server_flag     = false
      client_flag     = true
    }
    "konnectivity-server-cluster" = {
      backend         = "control-plane"
      allowed_domains = ["konnectivity"]
      organization    = "konnectivity"
      server_flag     = true,
      client_flag     = false
    }
    "konnectivity-agent" = {
      backend         = "control-plane"
      allowed_domains = ["konnectivity"]
      organization    = "konnectivity"
      server_flag     = true,
      client_flag     = false
    }
  }

  backend            = vault_mount.pki_control_plane.path
  name               = each.key
  ttl                = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits           = var.specs.pki.kubernetes_apiserver.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  allowed_domains    = try(each.value.allowed_domains, null)
  enforce_hostnames  = false
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou           = ["kubernetes"]
  organization = try([each.value.organization], null)
}

// Aggregation Layer PKI

resource "vault_mount" "pki_aggregation_layer" {
  path        = "pki/platform/kubernetes/aggregation-layer"
  description = "Kubernetes Aggregation-Layer CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.kubernetes_aggregation_layer.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.kubernetes_aggregation_layer.ttl_hours * 3600
}

resource "vault_pki_secret_backend_root_cert" "pki_aggregation_layer" {
  depends_on = [vault_mount.pki_aggregation_layer]

  backend  = vault_mount.pki_aggregation_layer.path
  type     = "internal"
  key_type = lower(var.specs.pki.kubernetes_aggregation_layer.algorithm)
  key_bits = var.specs.pki.kubernetes_aggregation_layer.rsa_bits
  ttl      = var.specs.pki.kubernetes_aggregation_layer.ttl_hours * 3600

  common_name    = var.specs.pki.kubernetes_aggregation_layer.common_name
  ou             = try(var.specs.pki.kubernetes_aggregation_layer.subject.organizational_unit, null)
  organization   = try(var.specs.pki.kubernetes_aggregation_layer.subject.organization, null)
  street_address = try(join("-", var.specs.pki.kubernetes_aggregation_layer.subject.street_address), null)
  postal_code    = try(var.specs.pki.kubernetes_aggregation_layer.subject.postal_code, null)
  locality       = try(var.specs.pki.kubernetes_aggregation_layer.subject.locality, null)
  province       = try(var.specs.pki.kubernetes_aggregation_layer.subject.province, null)
  country        = try(var.specs.pki.kubernetes_aggregation_layer.subject.country, null)
}

resource "vault_pki_secret_backend_config_urls" "pki_aggregation_layer" {
  depends_on = [vault_mount.pki_aggregation_layer]

  backend              = vault_mount.pki_aggregation_layer.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_aggregation_layer.path}/ca"]
}

resource "vault_pki_secret_backend_role" "pki_aggregation_layer" {
  depends_on = [vault_mount.pki_aggregation_layer]
  for_each = {
    "metrics-server" = {
      server_flag = true,
      client_flag = false
    }
    "apiserver" = {
      server_flag = false,
      client_flag = true
    }
  }

  backend            = vault_mount.pki_aggregation_layer.path
  name               = each.key
  ttl                = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits           = var.specs.pki.kubernetes_apiserver.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  allowed_domains    = try(each.value.allowed_domains, null)
  enforce_hostnames  = false
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou           = ["kubernetes"]
  organization = try([each.value.organization], null)
}

// Clients PKI

resource "vault_mount" "pki_client" {
  path        = "pki/platform/kubernetes/client"
  description = "Kubernetes Client CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.kubernetes_client.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.kubernetes_client.ttl_hours * 3600
}

resource "vault_pki_secret_backend_root_cert" "pki_client" {
  depends_on = [vault_mount.pki_client]

  backend  = vault_mount.pki_client.path
  type     = "internal"
  key_type = lower(var.specs.pki.kubernetes_client.algorithm)
  key_bits = var.specs.pki.kubernetes_client.rsa_bits
  ttl      = var.specs.pki.kubernetes_client.ttl_hours * 3600

  common_name    = var.specs.pki.kubernetes_client.common_name
  ou             = try(var.specs.pki.kubernetes_client.subject.organizational_unit, null)
  organization   = try(var.specs.pki.kubernetes_client.subject.organization, null)
  street_address = try(join("-", var.specs.pki.kubernetes_client.subject.street_address), null)
  postal_code    = try(var.specs.pki.kubernetes_client.subject.postal_code, null)
  locality       = try(var.specs.pki.kubernetes_client.subject.locality, null)
  province       = try(var.specs.pki.kubernetes_client.subject.province, null)
  country        = try(var.specs.pki.kubernetes_client.subject.country, null)
}

resource "vault_pki_secret_backend_config_urls" "pki_client" {
  depends_on = [vault_mount.pki_client]

  backend              = vault_mount.pki_client.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_client.path}/ca"]
}

resource "vault_pki_secret_backend_role" "pki_client" {
  depends_on = [vault_mount.pki_client]
  for_each = {
    "operator-admin" = {
      allowed_domains = ["cluster-admin"]
      organization    = "system:masters"
      server_flag     = false
      client_flag     = true
    }
  }

  backend            = vault_mount.pki_client.path
  name               = each.key
  ttl                = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits           = var.specs.pki.kubernetes_apiserver.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  allowed_domains    = try(each.value.allowed_domains, null)
  enforce_hostnames  = false
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou           = ["kubernetes"]
  organization = try([each.value.organization], null)
}

// Service Account Key Pair

resource "tls_private_key" "service_account" {
  algorithm   = upper(var.specs.pki.service_account.algorithm)
  ecdsa_curve = try(var.specs.pki.service_account.ecdsa_curve, null)
  rsa_bits    = try(var.specs.pki.service_account.rsa_bits, null)
}

resource "vault_generic_secret" "secret_service_account_keypair" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/service-account"

  data_json = jsonencode({
    private_key = tls_private_key.service_account.private_key_pem,
    public_key  = tls_private_key.service_account.public_key_pem
  })
}

// Kubelet PKI

resource "vault_mount" "pki_kubelet" {
  path        = "pki/platform/kubernetes/kubelet"
  description = "Kubernetes Kubelets CA"

  type                      = "pki"
  default_lease_ttl_seconds = var.specs.pki.kubernetes_kubelet.ttl_hours * 3600
  max_lease_ttl_seconds     = var.specs.pki.kubernetes_kubelet.ttl_hours * 3600
}

resource "tls_private_key" "kubelet_ca" {
  algorithm   = upper(var.specs.pki.kubernetes_kubelet.algorithm)
  ecdsa_curve = try(var.specs.pki.kubernetes_kubelet.ecdsa_curve, null)
  rsa_bits    = try(var.specs.pki.kubernetes_kubelet.rsa_bits, null)
}

resource "tls_self_signed_cert" "kubelet_ca" {
  private_key_pem = tls_private_key.kubelet_ca.private_key_pem

  subject {
    common_name         = var.specs.pki.kubernetes_kubelet.common_name
    country             = try(var.specs.pki.kubernetes_kubelet.subject.country, null)
    locality            = try(var.specs.pki.kubernetes_kubelet.subject.locality, null)
    organization        = try(var.specs.pki.kubernetes_kubelet.subject.organization, null)
    organizational_unit = try(var.specs.pki.kubernetes_kubelet.subject.organizational_unit, null)
    postal_code         = try(var.specs.pki.kubernetes_kubelet.subject.postal_code, null)
    province            = try(var.specs.pki.kubernetes_kubelet.subject.province, null)
    street_address      = try(var.specs.pki.kubernetes_kubelet.subject.street_address, null)
  }

  is_ca_certificate     = true
  validity_period_hours = var.specs.pki.kubernetes_kubelet.ttl_hours
  allowed_uses = [
    "cert_signing",
  ]
}

resource "vault_pki_secret_backend_config_ca" "pki_kubelet" {
  depends_on = [vault_mount.pki_kubelet]
  backend    = vault_mount.pki_kubelet.path

  pem_bundle = "${tls_private_key.kubelet_ca.private_key_pem}${tls_self_signed_cert.kubelet_ca.cert_pem}"
}

resource "vault_pki_secret_backend_config_urls" "pki_kubelet" {
  depends_on = [vault_mount.pki_kubelet]

  backend              = vault_mount.pki_kubelet.path
  issuing_certificates = ["https://${var.specs.vault.endpoint}:8200/v1/${vault_mount.pki_kubelet.path}/ca"]
}

resource "vault_pki_secret_backend_role" "pki_kubelet" {
  depends_on = [vault_mount.pki_kubelet]
  for_each = {
    "apiserver" = {
      organization = "system:masters"
      server_flag  = false,
      client_flag  = true
    }
  }

  backend            = vault_mount.pki_kubelet.path
  name               = each.key
  ttl                = var.specs.pki.kubernetes_apiserver.ttl_hours * 3600 # TODO: set ttl configurable
  key_type           = lower(var.specs.pki.kubernetes_apiserver.algorithm)
  key_bits           = var.specs.pki.kubernetes_apiserver.rsa_bits
  key_usage          = ["DigitalSignature", "KeyEncipherment"]
  allow_ip_sans      = true
  allow_bare_domains = true
  allow_any_name     = true
  allowed_domains    = try(each.value.allowed_domains, null)
  enforce_hostnames  = false
  server_flag        = each.value.server_flag
  client_flag        = each.value.client_flag

  ou           = ["kubernetes"]
  organization = try([each.value.organization], null)
}

// Also store the CA certificate & private key in the generic secret backend as it's needed for some
// control plane components (e.g. kube-controller-manager)

resource "vault_generic_secret" "kubelet_pki" {
  depends_on = [vault_mount.secret_kubernetes]
  path       = "${vault_mount.secret_kubernetes.path}/kubelet-pki"

  data_json = jsonencode({
    private_key = tls_private_key.kubelet_ca.private_key_pem
    certificate = tls_self_signed_cert.kubelet_ca.cert_pem
  })
}

// Kubernetes Cloud integration

resource "exoscale_iam_access_key" "ccm_access_key" {
  name = "${var.specs.infrastructure.name}-cloud-controller-manager"

  operations = [
    "add-service-to-load-balancer",
    "create-load-balancer",
    "delete-load-balancer",
    "delete-load-balancer-service",
    "get-instance",
    "get-instance-type",
    "get-load-balancer",
    "get-load-balancer-service",
    "get-operation",
    "list-instances",
    "list-load-balancers",
    "list-zones",
    "reset-load-balancer-field",
    "reset-load-balancer-service-field",
    "update-load-balancer",
    "update-load-balancer-service",
  ]
}

resource "vault_generic_secret" "ccm_access_key" {
  path = "kv/platform/exoscale/cloud-controller-manager"

  data_json = jsonencode({
    api_key    = exoscale_iam_access_key.ccm_access_key.key
    api_secret = exoscale_iam_access_key.ccm_access_key.secret
  })
}

resource "exoscale_iam_access_key" "autoscaler_access_key" {
  name = "${var.specs.infrastructure.name}-cluster-autoscaler"

  operations = [
    "evict-instance-pool-members",
    "get-instance-pool",
    "get-instance",
    "get-operation",
    "get-quota",
    "scale-instance-pool",
  ]
}

resource "vault_generic_secret" "autoscaler_access_key" {
  path = "kv/platform/exoscale/cluster-autoscaler"

  data_json = jsonencode({
    api_key    = exoscale_iam_access_key.autoscaler_access_key.key
    api_secret = exoscale_iam_access_key.autoscaler_access_key.secret
  })
}

// Policies

resource "vault_policy" "kubernetes_control_plane" {
  name = local.cluster_name

  policy = <<EOT
## API server
path "pki/platform/kubernetes/etcd/cert/ca_chain" {
  capabilities = ["read"]
}

path "pki/platform/kubernetes/etcd/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_control_plane.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_client.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_control_plane.path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_aggregation_layer.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_aggregation_layer.path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_kubelet.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_kubelet.path}/issue/apiserver" {
  capabilities = ["create", "update"]
}

#path "$ {vault_mount.pki_deployment["core"].path}/cert/ca_chain" {
#  capabilities = ["read"]
#

path "${vault_generic_secret.secret_service_account_keypair.path}" {
  capabilities = ["read"]
}

path "${vault_generic_secret.secret_encryption_keys.path}" {
  capabilities = ["read"]
}

## Controller manager

path "${vault_mount.pki_control_plane.path}/issue/controller-manager" {
  capabilities = ["create", "update"]
}

path "${vault_generic_secret.kubelet_pki.path}" {
  capabilities = ["read"]
}

# + path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_aggregation_layer.path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_kubelet.path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_generic_secret.secret_service_account_keypair.path}" { capabilities = ["read"] }

## Scheduler

path "${vault_mount.pki_control_plane.path}/issue/scheduler" {
  capabilities = ["create", "update"]
}

# + path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }
# + path "${vault_mount.pki_kubelet.path}/cert/ca_chain" { capabilities = ["read"] }

## Konnectivity (server)

path "${vault_mount.pki_control_plane.path}/issue/konnectivity" {
  capabilities = ["create", "update"]
}

path "${vault_mount.pki_control_plane.path}/issue/konnectivity-server-cluster" {
  capabilities = ["create", "update"]
}

# + path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }

## Exoscale cloud controller manager

path "${vault_mount.pki_control_plane.path}/issue/cloud-controller-manager" {
  capabilities = ["create", "update"]
}

path "/kv/platform/exoscale/cloud-controller-manager" {
  capabilities = ["read"]
}

# + path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }

## Cluster autoscaler

path "${vault_mount.pki_control_plane.path}/issue/cluster-autoscaler" {
  capabilities = ["create", "update"]
}

path "/kv/platform/exoscale/cluster-autoscaler" {
  capabilities = ["read"]
}

# + path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }

## Admin client

path "${vault_mount.pki_client.path}/cert/ca_chain" {
  capabilities = ["read"]
}

path "${vault_mount.pki_client.path}/issue/operator-admin" {
  capabilities = ["create", "update"]
}

## Metrics server

# path "${vault_mount.pki_control_plane.path}/cert/ca_chain" { capabilities = ["read"] }
# path "${vault_mount.pki_aggregation_layer.path}/cert/ca_chain" { capabilities = ["read"] }

path "${vault_mount.pki_aggregation_layer.path}/issue/metrics-server" {
  capabilities = ["create", "update"]
}

EOT
}

// Client certificate (for deployment bootstraping only)

resource "vault_pki_secret_backend_cert" "operator" {
  depends_on = [ vault_pki_secret_backend_root_cert.pki_client ]

  backend     = vault_mount.pki_client.path
  name        = "operator-admin"
  common_name = "cluster-admin"
  ttl         = 3600
}
