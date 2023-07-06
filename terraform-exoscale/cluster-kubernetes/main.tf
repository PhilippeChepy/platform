// Kubelet bootstrap token
// REF: https://kubernetes.io/docs/reference/access-authn-authz/bootstrap-tokens/

resource "random_string" "token_id" {
  length  = 6
  lower   = true
  numeric = true
  special = false
  upper   = false
}

resource "random_string" "token_secret" {
  length  = 16
  lower   = true
  numeric = true
  special = false
  upper   = false
}

// Compute resources

resource "exoscale_anti_affinity_group" "cluster" {
  name        = local.cluster_name
  description = "Hashicorp Vault (${local.cluster_name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${local.cluster_name}-cluster"
}

resource "exoscale_security_group" "clients" {
  name = "${local.cluster_name}-clients"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "TCP|6443|cluster" = { port = "6443", security_group = exoscale_security_group.cluster.id }
    "TCP|6443|clients" = { port = "6443", security_group = exoscale_security_group.clients.id }
    "TCP|6444|exoscale" = { port = "6444", public_security_group = "public-nlb-healthcheck-sources" }
    }, merge([
      for client in var.kubelet_security_groups : {
        "TCP|6443|sg:${client.name}" = { port = "6443", security_group = client.id }
        "TCP|8091|sg:${client.name}" = { port = "8091", security_group = client.id }
      }
    ]...), merge([
      for cidr in concat([for specs in var.specs.operators : specs.networks]...) : {
        "TCP|22|cidr:${cidr}"   = { port = "22", cidr = cidr },
        "TCP|6443|cidr:${cidr}" = { port = "6443", cidr = cidr }
      }
    ]...)
  )

  security_group_id      = exoscale_security_group.cluster.id
  protocol               = "TCP"
  type                   = "INGRESS"
  start_port             = each.value["port"]
  end_port               = each.value["port"]
  cidr                   = try(each.value.cidr, null)
  user_security_group_id = try(each.value.security_group, null)
  public_security_group = try(each.value.public_security_group, null)
}


resource "exoscale_nlb_service" "endpoint" {
  nlb_id      = var.internal_nlb.id
  zone        = var.specs.infrastructure.zone
  name        = "kubernetes"
  description = "Kubernetes API server service"

  instance_pool_id = exoscale_instance_pool.cluster.id
  protocol         = "tcp"
  port             = 6443
  target_port      = 6443
  strategy         = "round-robin"

  healthcheck {
    mode     = "http"
    port     = 6444
    uri      = "/healthz"
    interval = 5
    timeout  = 2
    retries  = 2
  }
}

resource "exoscale_instance_pool" "cluster" {
  zone               = var.specs.infrastructure.zone
  name               = local.cluster_name
  size               = var.specs.kubernetes.pool.size
  template_id        = var.specs.templates.kubernetes
  instance_type      = var.specs.kubernetes.pool.offering
  disk_size          = var.specs.kubernetes.pool.disk_size_gb
  key_pair           = var.ssh_key
  instance_prefix    = local.cluster_name
  ipv6               = true
  affinity_group_ids = [exoscale_anti_affinity_group.cluster.id]
  security_group_ids = [exoscale_security_group.cluster.id]
  user_data = templatefile("${path.module}/templates/user-data", {
    etcd_cluster_servers           = var.etcd_servers
    etcd_cluster_ip_address        = var.internal_nlb.ip_address
    kubernetes_cluster_ip_address  = var.internal_nlb.ip_address
    kubernetes_cluster_domain      = var.specs.kubernetes.domain
    kubernetes_cluster_internal_ip = var.specs.kubernetes.network.inet4.kubernetes
    kubernetes_cluster_name        = local.cluster_name
    kubernetes_pod_cidr_ipv4       = var.specs.kubernetes.network.inet4.pod_cidr
    kubernetes_pod_cidr_ipv6       = var.specs.kubernetes.network.inet6.pod_cidr
    kubernetes_service_cidr_ipv4   = var.specs.kubernetes.network.inet4.svc_cidr
    kubernetes_service_cidr_ipv6   = var.specs.kubernetes.network.inet6.svc_cidr
    oidc_issuer_url                = "https://idp.${var.specs.infrastructure.domain}" # TODO: create a configuration option
    oidc_client_id                 = "kubectl"
    oidc_username_claim            = "name"
    oidc_groups                    = "groups"
    vault_ca_pem                    = base64encode(try(file("${path.module}/../../artifacts/ca-certificate.pem"), "")) # HACK: fallback to empty string because of Terraform trying to interpolate while the module is not (yet) enabled
    vault_cluster_address           = "https://${var.internal_nlb.ip_address}:8200"
    vault_cluster_name              = "${var.specs.infrastructure.name}-vault"
    vault_cluster_healthcheck_url   = "https://${var.internal_nlb.ip_address}:8200/v1/sys/health"
    zone                           = var.specs.infrastructure.zone

    kubelet_bootstrap_manifests = base64encode(templatefile("${path.module}/templates/manifests/kubelet-bootstrap-token.yaml", {
      token_id     = random_string.token_id.result
      token_secret = random_string.token_secret.result
    }))
  })

  # TODO: labels
}
