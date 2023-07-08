// Root CA certificate for internal endpoints

# TODO: update the bootstrap process of vault in order to avoid building the CA here.
resource "tls_private_key" "root_ca" {
  algorithm   = upper(local.specs.pki.root.algorithm)
  ecdsa_curve = try(local.specs.pki.root.ecdsa_curve, null)
  rsa_bits    = try(local.specs.pki.root.rsa_bits, null)
}

resource "tls_self_signed_cert" "root_ca" {
  private_key_pem = tls_private_key.root_ca.private_key_pem

  subject {
    common_name         = local.specs.pki.root.common_name
    country             = try(local.specs.pki.root.subject.country, null)
    locality            = try(local.specs.pki.root.subject.locality, null)
    organization        = try(local.specs.pki.root.subject.organization, null)
    organizational_unit = try(local.specs.pki.root.subject.organizational_unit, null)
    postal_code         = try(local.specs.pki.root.subject.postal_code, null)
    province            = try(local.specs.pki.root.subject.province, null)
    street_address      = try(local.specs.pki.root.subject.street_address, null)
  }

  is_ca_certificate     = true
  validity_period_hours = local.specs.pki.root.ttl_hours
  allowed_uses = [
    "cert_signing",
  ]
}

resource "local_file" "root_ca_certificate_pem" {
  content  = tls_self_signed_cert.root_ca.cert_pem
  filename = "${path.module}/../artifacts/ca-certificate.pem"
}

resource "local_sensitive_file" "root_ca_private_key_pem" {
  content         = tls_private_key.root_ca.private_key_pem
  filename        = "${path.module}/../artifacts/ca-certificate.key"
  file_permission = 0600
}

// Cluster management & SSH key

resource "tls_private_key" "management_key" {
  algorithm   = upper(local.specs.ssh.algorithm)
  ecdsa_curve = try(local.specs.ssh.ecdsa_curve, null)
  rsa_bits    = try(local.specs.ssh.rsa_bits, null)
}

resource "exoscale_ssh_key" "management_key" {
  name       = "${local.specs.infrastructure.name}-management"
  public_key = tls_private_key.management_key.public_key_openssh
}

resource "local_file" "management_key" {
  content         = tls_private_key.management_key.private_key_openssh
  filename        = "${path.module}/../artifacts/id_${lower(local.specs.ssh.algorithm)}"
  file_permission = 0600
}

// The intenal network load balancer

resource "exoscale_nlb" "load_balancer" {
  zone        = local.specs.infrastructure.zone
  name        = "${local.specs.infrastructure.name}-internal"
  description = "Entrypoint for the internal infrastructure endpoints"
}

// Backup storage

resource "aws_s3_bucket" "backup" {
  for_each = toset(["etcd", "vault"])
  bucket   = "${local.specs.backup.prefix}-${local.specs.infrastructure.name}-${each.value}.${local.specs.backup.zone}"

  # Disable unsupported features
  lifecycle {
    ignore_changes = [
      object_lock_configuration,
    ]
  }
}

// Vault cluster
module "cluster_vault" {
  source   = "./cluster-vault"
  for_each = local.enabled_module.cluster_vault

  specs        = local.specs
  internal_nlb = exoscale_nlb.load_balancer
  ssh_key      = exoscale_ssh_key.management_key.name
  
  client_security_group      = toset(concat([
    can(module.cluster_etcd["enabled"].cluster_security_group.name) ? [module.cluster_etcd["enabled"].cluster_security_group] : [],
    can(module.cluster_kubernetes["enabled"].cluster_security_group.name) ? [module.cluster_kubernetes["enabled"].cluster_security_group] : []
  ]...))
}

resource "local_file" "vault_inventory" {
  for_each = local.enabled_module.cluster_vault
  content  = module.cluster_vault["enabled"].inventory
  filename = "${path.module}/../artifacts/vault-inventory.yml"
}

// Etcd cluster

module "cluster_etcd" {
  source   = "./cluster-etcd"
  for_each = local.enabled_module.cluster_etcd

  specs        = local.specs

  internal_nlb = exoscale_nlb.load_balancer
  ssh_key      = exoscale_ssh_key.management_key.name
  
  client_security_group      = toset(concat([
    can(module.cluster_kubernetes["enabled"].cluster_security_group.name) ? [module.cluster_kubernetes["enabled"].cluster_security_group] : []
  ]...))
}

resource "local_file" "etcd_inventory" {
  for_each = local.enabled_module.cluster_etcd
  content  = module.cluster_etcd["enabled"].inventory
  filename = "${path.module}/../artifacts/etcd-inventory.yml"
}

// Kubernetes

module "cluster_kubernetes" {
  source   = "./cluster-kubernetes"
  for_each = local.enabled_module.cluster_kubernetes

  specs        = local.specs

  internal_nlb = exoscale_nlb.load_balancer
  etcd_servers = join(",", [for instance in module.cluster_etcd["enabled"].instances : "https://${instance.public_ip_address}:2379"])
  ssh_key      = exoscale_ssh_key.management_key.name

  kubelet_security_groups = toset(concat([
    can(module.cluster_kubernetes_pools["enabled"].cluster_security_group.name) ? [module.cluster_kubernetes_pools["enabled"].cluster_security_group] : []
  ]...))
}

module "cluster_kubernetes_pools" {
  source   = "./cluster-kubernetes-pools"
  for_each = local.enabled_module.cluster_kubernetes_pools

  specs        = local.specs

  internal_nlb = exoscale_nlb.load_balancer
  ssh_key      = exoscale_ssh_key.management_key.name

  bootstrap_token = join(".", [
    module.cluster_kubernetes["enabled"].bootstrap_token.id,
    module.cluster_kubernetes["enabled"].bootstrap_token.secret
  ])
}

// Bootstrap manifests

resource "local_file" "bootstrap_cilium" {
  filename = "${path.module}/../artifacts/bootstrap-cilium.yaml"
  content  = templatefile("${path.module}/templates/cilium/manifests.yaml", {
    kubernetes_pod_network_inet4_cidr = local.specs.kubernetes.network.inet4.pod_cidr
    kubernetes_api_address = exoscale_nlb.load_balancer.ip_address
  })
}

resource "local_file" "bootstrap_coredns" {
  filename = "${path.module}/../artifacts/bootstrap-coredns.yaml"
  content  = templatefile("${path.module}/templates/coredns/manifests.yaml", {
    kubernetes_cluster_domain = local.specs.kubernetes.domain
    coredns_service_inet4_address = local.specs.kubernetes.network.inet4.dns
  })
}

resource "local_file" "bootstrap_cas_annotator" {
  filename = "${path.module}/../artifacts/bootstrap-cas-node-ignore-helper.yaml"
  content  = templatefile("${path.module}/templates/cas-node-ignore-helper/manifests.yaml", {
    platform_domain = local.specs.infrastructure.domain
  })
}

resource "local_file" "bootstrap_metrics_server" {
  filename = "${path.module}/../artifacts/bootstrap-metrics-server.yaml"
  content  = templatefile("${path.module}/templates/metrics-server/manifests.yaml", {
    platform_domain = local.specs.infrastructure.domain
  })
}

resource "local_file" "bootstrap_konnectivity_agent" {
  filename = "${path.module}/../artifacts/bootstrap-konnectivity-agent.yaml"
  content  = templatefile("${path.module}/templates/konnectivity-agent/manifests.yaml", {
    platform_domain = local.specs.infrastructure.domain
    api_server_address = try(module.cluster_kubernetes["enabled"].api_server_address, ["", ""])
  })
}
