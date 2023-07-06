// The intenal network load balancer

data "exoscale_nlb" "load_balancer" {
  zone = local.specs.infrastructure.zone
  name = "${local.specs.infrastructure.name}-internal"
}

// Vault configuration

module "config-vault-plugin-exoscale" {
  source   = "./config-plugin-exoscale"
  for_each = local.enabled_module.cluster_vault

  internal_nlb = data.exoscale_nlb.load_balancer
  specs        = local.specs
}

module "config-vault-pki-vault" {
  source     = "./config-vault"
  for_each   = local.enabled_module.cluster_vault
  depends_on = [module.config-vault-plugin-exoscale]

  specs          = local.specs
  root_ca_bundle = local.vault_root_ca_bundle
}

// Etcd cluster

module "config_vault_pki_etcd" {
  source     = "./config-etcd"
  for_each   = local.enabled_module.cluster_etcd
  depends_on = [module.config-vault-plugin-exoscale]

  specs = local.specs
}

// Kubernetes cluster

data "exoscale_nlb" "internal" {
  zone = local.specs.infrastructure.zone
  name = "${local.specs.infrastructure.name}-internal"
}

module "config_vault_pki_kubernetes" {
  source     = "./config-kubernetes"
  for_each   = local.enabled_module.cluster_kubernetes
  depends_on = [module.config-vault-plugin-exoscale]

  specs = local.specs
  internal_nlb = data.exoscale_nlb.internal
}

resource "local_file" "control_plane_ca_pem" {
  for_each = module.config_vault_pki_kubernetes

  content  = module.config_vault_pki_kubernetes[each.key].control_plane_ca_pem
  filename = "${path.module}/../artifacts/kubernetes-control-plane-ca.pem"
}

resource "local_file" "kubelet_ca_pem" {
  for_each = module.config_vault_pki_kubernetes

  content  = module.config_vault_pki_kubernetes[each.key].kubelet_ca_pem
  filename = "${path.module}/../artifacts/kubelet-ca.pem"
}

resource "local_file" "kubeconfig" {
  content  = try(module.config_vault_pki_kubernetes["enabled"].operator_kubeconfig, "")
  filename = "${path.module}/../artifacts/admin.kubeconfig"
}