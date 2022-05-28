locals {
  # Control plane CAs & deployment properties
  deployment_variables = {
    "provider:zone"                         = local.platform_zone
    "kubernetes:apiserver_ca_cert"          = base64encode(data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"])
    "kubernetes:aggregationlayer_ca_cert"   = base64encode(data.vault_generic_secret.kubernetes["aggregation-layer-ca"].data["ca_chain"])
    "kubernetes:kubelet_ca_cert"            = base64encode(data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"])
    "kubernetes:apiserver_service_ipv4"     = local.platform_components.kubernetes.apiserver_service_ipv4
    "kubernetes:apiserver_service_ipv6"     = local.platform_components.kubernetes.apiserver_service_ipv6
    "kubernetes:apiserver_ipv4"             = module.kubernetes_control_plane.cluster_ip_address
    "kubernetes:cluster_domain"             = local.platform_components.kubernetes.cluster_domain
    "kubernetes:pod_cidr_ipv4"              = local.platform_components.kubernetes.pod_cidr_ipv4
    "kubernetes:pod_cidr_ipv6"              = local.platform_components.kubernetes.pod_cidr_ipv6
    "kubernetes:dns_service_ipv4"           = local.platform_components.kubernetes.dns_service_ipv4
    "kubernetes:dns_service_ipv6"           = local.platform_components.kubernetes.dns_service_ipv6 // XXX: implement it in addition to ipv4
    "kubernetes:service_cidr_ipv4"          = local.platform_components.kubernetes.service_cidr_ipv4
    "kubernetes:service_cidr_ipv6"          = local.platform_components.kubernetes.service_cidr_ipv6
    "kubernetes:proxy_server_ipv4"          = module.kubernetes_control_plane.cluster_ip_address
    "vault:cluster_addr"                    = local.vault.url
    "vault:cluster_ca_cert"                 = base64encode(data.local_file.root_ca_certificate_pem.content)
    "vault:auth_path"                       = "auth/kubernetes/vault-agent-injector"
    "vault:path_pki_sign:aggregation_layer" = local.pki.pki_sign_aggregation_layer
  }

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

module "namespaces" {
  source = "./modules/kubernetes-namespace"
  for_each = toset([
    for _, spec in merge(
      local.platform_components.kubernetes.deployments.core,
      local.platform_components.kubernetes.deployments.core-addons
    ) : spec.namespace
    if spec.namespace != "kube-system"
  ])
  depends_on = [local_file.kubeconfig, module.kubernetes_control_plane]

  kubeconfig_path = "${path.module}/../artifacts/admin.kubeconfig"

  namespace = each.value
}

module "deployment_core" {
  source     = "./modules/kubernetes-deployment"
  for_each   = local.platform_components.kubernetes.deployments.core
  depends_on = [module.namespaces]

  kubeconfig_path = "${path.module}/../artifacts/admin.kubeconfig"

  deployment_namespace     = each.value.namespace
  deployment_manifest_file = "${path.module}/templates/${each.key}/${each.value.version}/manifests.yaml"
  deployment_variables     = local.deployment_variables

  service_account_tokens = try(each.value.service_account_tokens, {})

  readiness_checks = try(each.value.ready_on, [])
  templated        = try(each.value.templated, true)
}

module "deployment_core_addons" {
  source     = "./modules/kubernetes-deployment"
  for_each   = local.platform_components.kubernetes.deployments.core-addons
  depends_on = [module.deployment_core]

  kubeconfig_path = "${path.module}/../artifacts/admin.kubeconfig"

  deployment_namespace     = each.value.namespace
  deployment_manifest_file = "${path.module}/templates/${each.key}/${each.value.version}/manifests.yaml"
  deployment_variables     = local.deployment_variables

  service_account_tokens = try(each.value.service_account_tokens, {})

  readiness_checks = toset(try(each.value.ready_on, []))
  templated        = try(each.value.templated, true)
}

resource "vault_auth_backend" "kubernetes" {
  for_each = toset(concat(
    can(local.platform_components.kubernetes.deployments.core["cert-manager"]) ? [
      "cert-manager"
    ] : [],
    can(local.platform_components.kubernetes.deployments.core["vault-agent-injector"]) ? [
      "vault-agent-injector"
    ] : []
  ))

  type = "kubernetes"
  path = "kubernetes/${each.key}"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  for_each = merge(
    can(local.platform_components.kubernetes.deployments.core["cert-manager"]) &&
    can(local.platform_components.kubernetes.deployments.core-addons["metrics-server"]) ? {
      "metrics-server" = {
        backend = "cert-manager"
        token   = module.deployment_core_addons["metrics-server"].serviceaccount_tokens["metrics-server-vault-issuer"]
      }
    } : {},
    can(local.platform_components.kubernetes.deployments.core["vault-agent-injector"]) ? {
      "vault-agent-injector" = {
        backend = "vault-agent-injector"
        token   = module.deployment_core["vault-agent-injector"].serviceaccount_tokens["vault-server"]
      }
    } : {}
  )

  backend                = vault_auth_backend.kubernetes[each.value["backend"]].path
  kubernetes_host        = "https://${module.kubernetes_control_plane.cluster_ip_address}:6443"
  kubernetes_ca_cert     = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  token_reviewer_jwt     = each.value["token"] //kubernetes_secret.vault_token[each.key].data["token"]
  issuer                 = "kubernetes.default.svc.${local.platform_components.kubernetes.cluster_domain}"
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = merge(
    can(local.platform_components.kubernetes.deployments.core-addons["metrics-server"]) ? { "metrics-server" = {
      backend         = "cert-manager"
      namespace       = try(local.platform_components.kubernetes.deployments.core-addons["metrics-server"].namespace, null)
      service_account = "metrics-server"
    } } : {},
    can(local.platform_components.kubernetes.deployments.core-addons["cloud-controller-manager"]) ? { "cloud-controller-manager" = {
      backend   = "vault-agent-injector"
      namespace = try(local.platform_components.kubernetes.deployments.core-addons["cloud-controller-manager"].namespace, null)
    } } : {},
    can(local.platform_components.kubernetes.deployments.core-addons["cluster-autoscaler"]) ? { "cluster-autoscaler" = {
      backend   = "vault-agent-injector"
      namespace = try(local.platform_components.kubernetes.deployments.core-addons["cluster-autoscaler"].namespace, null)
    } } : {}
  )

  backend                          = vault_auth_backend.kubernetes[each.value["backend"]].path
  role_name                        = each.key
  bound_service_account_namespaces = [each.value["namespace"]]
  bound_service_account_names      = [try(each.value["service_account"], each.key)]                            # fallback = each.key
  token_policies                   = ["default", try(each.value["policy"], "platform-kubernetes-${each.key}")] # fallback = "platform-kubernetes-${each.key}"
  token_ttl                        = 3600
}

module "kubernetes_generic_nodepool" {
  source = "./modules/kubernetes-kubelet-pool"

  depends_on = [
    module.kubernetes_control_plane
  ]

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


resource "vault_pki_secret_backend_cert" "operator" {
  backend     = "pki/platform/kubernetes/client"
  name        = "operator-admin"
  common_name = "cluster-admin"
  ttl         = local.platform_default_tls_ttl.cert * 3600
}

resource "local_file" "kubeconfig" {
  content  = <<EOT
apiVersion: v1
clusters:
  - cluster:
      certificate-authority-data: ${base64encode(data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"])}
      server: https://${module.kubernetes_control_plane.cluster_ip_address}:6443
    name: ${local.platform_name}
contexts:
  - context:
      cluster: ${local.platform_name}
      user: default
    name: ${local.platform_name}
current-context: ${local.platform_name}
kind: Config
preferences: {}
users:
  - name: default
    user:
      client-certificate-data: ${base64encode(vault_pki_secret_backend_cert.operator.certificate)}
      client-key-data: ${base64encode(vault_pki_secret_backend_cert.operator.private_key)}
EOT
  filename = "${path.module}/../artifacts/admin.kubeconfig"
}