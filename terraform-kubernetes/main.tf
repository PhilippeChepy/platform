locals {

  # Settings for Vault clients

  vault_settings = {
    url                = local.vault.url
    cluster_name       = "${local.platform_name}-vault"
    ca_certificate_pem = data.local_file.root_ca_certificate_pem.content
    healthcheck_url    = "https://${local.vault.ip_address}:8200/v1/sys/health"
  }

  # Settings for Kubernetes clients

  kubernetes_settings = {
    apiserver_cluster_ip_address = module.kubernetes_control_plane.cluster_ip_address
    cluster_domain               = local.platform_components.kubernetes.cluster_domain
    controlplane_ca_pem          = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
    dns_service_ipv4             = local.platform_components.kubernetes.dns_service_ipv4
    dns_service_ipv6             = local.platform_components.kubernetes.dns_service_ipv6
    kubelet_authentication_token = join("", [
      data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"],
      ".",
      data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"],
    ])
    kubelet_ca_pem = data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"]
  }
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
    bootstrap-token      = "kv/platform/kubernetes/kubelet-bootstrap-token"
  }

  path = each.value
}

module "etcd_cluster" {
  source = "./modules/etcd"
  zone   = local.platform_zone
  name   = "${local.platform_name}-etcd"

  template_id = local.platform_components.kubernetes.templates.etcd
  admin_security_groups = {
    operator = local.base.operator_security_group
  }
  client_security_groups = {
    operator = local.base.operator_security_group,
    # module.kubernetes_control_plane.controlplane_security_group_id
  }
  additional_security_groups = {
    vault = local.vault.client_security_group
  }
  ssh_key = "${local.platform_name}-management"

  labels = {
    name = local.platform_name
    zone = local.platform_zone
    role = "etcd"
  }

  domain       = local.platform_domain
  cluster_size = 3

  vault = local.vault_settings
}

module "kubernetes_control_plane" {
  source = "./modules/kubernetes-control-plane"
  zone   = local.platform_zone
  name   = "${local.platform_name}-kubernetes"

  template_id = local.platform_components.kubernetes.templates.control_plane
  admin_security_groups = {
    operator = local.base.operator_security_group
  }
  client_security_groups = {
    operator = local.base.operator_security_group,
    vault    = local.vault.server_security_group,
  }
  additional_security_groups = {
    vault = local.vault.client_security_group,
    etcd  = module.etcd_cluster.client_security_group_id
  }
  ssh_key = "${local.platform_name}-management"

  labels = {
    name = local.platform_name
    zone = local.platform_zone
    role = "kubernetes-control-plane"
  }

  domain       = local.platform_domain
  cluster_size = 2

  vault = local.vault_settings

  etcd = {
    address         = module.etcd_cluster.url
    healthcheck_url = "http://${module.etcd_cluster.cluster_ip_address}:2378/healthz"
  }

  kubernetes = {
    apiserver_service_ipv4 = local.platform_components.kubernetes.apiserver_service_ipv4
    bootstrap_token_id     = data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"]
    bootstrap_token_secret = data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"]
    cluster_domain         = local.platform_components.kubernetes.cluster_domain
    service_cidr_ipv4      = local.platform_components.kubernetes.service_cidr_ipv4
    service_cidr_ipv6      = local.platform_components.kubernetes.service_cidr_ipv6
  }
}

module "kubernetes_generic_nodepool" {
  source = "./modules/kubernetes-kubelet-pool"

  for_each = {
    "general" = {
      size                 = 3
      instance_type        = "standard.small"
      security_group_rules = {}
      disk_size            = 20
    }
  }

  zone = local.platform_zone
  name = "${local.platform_name}-${each.key}"

  template_id   = local.platform_components.kubernetes.templates.kubelet
  instance_type = each.value.instance_type
  admin_security_groups = {
    operator = local.base.operator_security_group
  }
  client_security_groups = {
    operator = local.base.operator_security_group,
  }
  additional_security_groups = {
    vault   = local.vault.client_security_group, # for vault-agent-injector
    kubelet = module.kubernetes_control_plane.kubelet_security_group_id
  }
  ssh_key = "${local.platform_name}-management"

  labels = {
    name     = local.platform_name
    zone     = local.platform_zone
    role     = "kubernetes-kubelet-pool"
    instance = each.key
  }

  domain     = local.platform_domain
  pool_size  = each.value.size
  kubernetes = local.kubernetes_settings
}
