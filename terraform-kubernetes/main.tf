locals {
  # Settings for Vault clients

  vault_settings = {
    url                = local.vault.url
    cluster_name       = "${local.platform_name}-vault"
    ca_certificate_pem = data.local_file.root_ca_certificate_pem.content
    healthcheck_url    = "${local.vault.url}/v1/sys/health"
  }

  # Settings for Kubernetes clients

  kubernetes_settings = {
    apiserver_url             = module.kubernetes_control_plane.url
    apiserver_healthcheck_url = module.kubernetes_control_plane.healthcheck_url
    cluster_domain            = local.platform_components.kubernetes.cluster_domain
    controlplane_ca_pem       = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
    dns_service_ipv4          = local.platform_components.kubernetes.dns_service_ipv4
    dns_service_ipv6          = local.platform_components.kubernetes.dns_service_ipv6
    kubelet_authentication_token = join("", [
      data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"],
      ".",
      data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"],
    ])
    kubelet_ca_pem = data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"]
  }

  # Ingress nodes

  ingress_security_group_rules = {
    http      = { protocol = "TCP", type = "INGRESS", port = 80, cidr = "0.0.0.0/0" },
    https     = { protocol = "TCP", type = "INGRESS", port = 443, cidr = "0.0.0.0/0" },
    admission = { protocol = "TCP", type = "INGRESS", port = 8443, security_group_id = module.kubernetes_control_plane.kubelet_security_group_id },
  }
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
    bootstrap-token      = "kv/platform/kubernetes/kubelet-bootstrap-token"
    service_account_key  = "kv/platform/kubernetes/service-account"
  }

  path = each.value
}

data "exoscale_nlb" "endpoint" {
  zone = local.platform_zone
  id   = local.base.endpoint_loadbalencer_id
}

module "etcd_cluster" {
  source = "./modules/etcd"
  zone   = local.platform_zone
  name   = "${local.platform_name}-etcd"

  template_id                 = local.platform_components.kubernetes.templates.etcd
  admin_security_groups       = { operator = local.base.operator_security_group }
  client_security_groups      = { operator = local.base.operator_security_group }
  healthcheck_security_groups = { exoscale = local.base.exoscale_security_group }
  additional_security_groups  = { vault = local.vault.client_security_group }
  ssh_key                     = "${local.platform_name}-management"

  labels = {
    name = local.platform_name
    zone = local.platform_zone
    role = "etcd"
  }

  domain       = local.platform_domain
  cluster_size = 3

  vault = local.vault_settings
  backup = {
    bucket = local.rclone.etcd.bucket
    zone   = local.rclone.etcd.zone
  }

  endpoint_loadbalancer_id = local.base.endpoint_loadbalencer_id
}

module "kubernetes_control_plane" {
  source = "./modules/kubernetes-control-plane"
  zone   = local.platform_zone
  name   = "${local.platform_name}-kubernetes"

  template_id                 = local.platform_components.kubernetes.templates.control_plane
  admin_security_groups       = { operator = local.base.operator_security_group }
  client_security_groups      = { operator = local.base.operator_security_group, vault = local.vault.server_security_group }
  healthcheck_security_groups = { exoscale = local.base.exoscale_security_group }
  additional_security_groups  = { vault = local.vault.client_security_group, etcd = module.etcd_cluster.client_security_group_id }
  ssh_key                     = "${local.platform_name}-management"

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
    healthcheck_url = module.etcd_cluster.healthcheck_url
  }

  kubernetes = {
    apiserver_service_ipv4 = local.platform_components.kubernetes.apiserver_service_ipv4
    bootstrap_token_id     = data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"]
    bootstrap_token_secret = data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"]
    cluster_domain         = local.platform_components.kubernetes.cluster_domain
    service_cidr_ipv4      = local.platform_components.kubernetes.service_cidr_ipv4
    service_cidr_ipv6      = local.platform_components.kubernetes.service_cidr_ipv6
  }

  oidc = {
    claim = {
      groups   = "groups"
      username = "name"
    }
    client_id  = "kubectl"
    issuer_url = "https://dex.${local.platform_domain}"
  }

  endpoint_loadbalancer_id = local.base.endpoint_loadbalencer_id
}

resource "exoscale_nlb" "ingress" {
  for_each = local.platform_components.kubernetes.ingresses

  zone        = local.platform_zone
  name        = "${local.platform_name}-ingress-${each.key}"
  description = "Ingress load balancer (${each.key})"

  lifecycle {
    prevent_destroy = true
  }
}

resource "exoscale_nlb_service" "ingress_http" {
  for_each = local.platform_components.kubernetes.ingresses

  zone = local.platform_zone
  name = "${local.platform_name}-ingress-${each.key}-http"

  nlb_id           = exoscale_nlb.ingress[each.key].id
  instance_pool_id = module.kubernetes_nodepool["ingress-${each.key}"].instance_pool_id

  protocol    = "tcp"
  port        = 80
  target_port = 80
  strategy    = "round-robin"

  healthcheck {
    mode     = "tcp"
    port     = 80
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

resource "exoscale_nlb_service" "ingress_https" {
  for_each = local.platform_components.kubernetes.ingresses

  zone = local.platform_zone
  name = "${local.platform_name}-ingress-${each.key}-https"

  nlb_id           = exoscale_nlb.ingress[each.key].id
  instance_pool_id = module.kubernetes_nodepool["ingress-${each.key}"].instance_pool_id

  protocol    = "tcp"
  port        = 443
  target_port = 443
  strategy    = "round-robin"

  healthcheck {
    mode     = "tcp"
    port     = 443
    interval = 5
    timeout  = 3
    retries  = 1
  }
}

module "kubernetes_nodepool" {
  source = "./modules/kubernetes-kubelet-pool"

  depends_on = [
    module.kubernetes_control_plane
  ]

  for_each = merge({
    "general" = {
      size                 = 3
      instance_type        = "standard.small"
      security_group_rules = {}
      disk_size            = 20
    }
    }, {
    for name, ingress in local.platform_components.kubernetes.ingresses :
    "ingress-${name}" => {
      size                 = ingress.pool_size
      instance_type        = "standard.tiny"
      security_group_rules = local.ingress_security_group_rules
      disk_size            = 20
      labels               = { (split("=", ingress.label)[0]) = split("=", ingress.label)[1] }
      taints               = { (split("=", ingress.label)[0]) = { value = split("=", ingress.label)[1], effect = "NoSchedule" } }
    }
  })

  zone = local.platform_zone
  name = "${local.platform_name}-${each.key}"

  template_id   = local.platform_components.kubernetes.templates.kubelet
  instance_type = each.value.instance_type
  admin_security_groups = {
    operator = local.base.operator_security_group
  }
  additional_security_groups = {
    vault   = local.vault.client_security_group, # for vault-related agents
    kubelet = module.kubernetes_control_plane.kubelet_security_group_id
  }
  security_group_rules = each.value.security_group_rules
  ssh_key              = "${local.platform_name}-management"

  labels = {
    name     = local.platform_name
    zone     = local.platform_zone
    role     = "kubernetes-kubelet-pool"
    instance = each.key
  }

  domain         = local.platform_domain
  pool_size      = each.value.size
  kubernetes     = local.kubernetes_settings
  kubelet_labels = try(each.value.labels, {})
  kubelet_taints = try(each.value.taints, {})
}

# Services interactions

## Vault <---> Kubernetes deployments

locals {
  vault_deployment_roles = merge({
    for name, deployment in merge(local.platform_components.kubernetes.deployments.core, local.platform_components.kubernetes.deployments.bootstrap) :
    name => {
      namespace       = deployment.namespace
      service-account = deployment.vault-service-account
    }
    if try(deployment.vault-service-account, null) != null
    },
    concat([
      for name, ingress in local.platform_components.kubernetes.ingresses : [
        {
          for _, deployment in ingress.deployments :
          "ingress-${name}-${deployment}" => {
            namespace       = try(local.platform_components.kubernetes.deployments.ingress[deployment].namespace, "ingress-nginx-${name}")
            service-account = "ingress-${name}-${local.platform_components.kubernetes.deployments.ingress[deployment].vault-service-account}"
          }
          if try(local.platform_components.kubernetes.deployments.ingress[deployment].vault-service-account, null) != null
        }
      ]
    ]...)...
  )
}

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on         = [vault_auth_backend.kubernetes]
  backend            = "kubernetes"
  kubernetes_host    = module.kubernetes_control_plane.url
  kubernetes_ca_cert = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  pem_keys           = [chomp(data.vault_generic_secret.kubernetes["service_account_key"].data["public_key"])]
}

resource "vault_kubernetes_auth_backend_role" "roles" {
  depends_on = [vault_auth_backend.kubernetes]
  for_each   = local.vault_deployment_roles

  backend                          = "kubernetes"
  role_name                        = each.key
  bound_service_account_namespaces = [each.value.namespace]
  bound_service_account_names      = [each.value.service-account]
  token_policies                   = ["default", "platform-deployment-${each.key}"]
  token_ttl                        = 3600
}

# User interactions

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
      server: ${module.kubernetes_control_plane.url}
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

resource "local_file" "user_kubeconfig" {
  content  = <<EOT
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${base64encode(data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"])}
    server: ${module.kubernetes_control_plane.url}
  name: ${local.platform_name}
contexts:
- context:
    cluster: ${local.platform_name}
    user: oidc
  name: ${local.platform_name}
current-context: ${local.platform_name}
kind: Config
preferences: {}
users:
- name: oidc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - oidc-login
      - get-token
      - --oidc-issuer-url=https://dex.${local.platform_domain}
      - --oidc-client-id=kubectl
      - --oidc-client-secret=kubectl-secret
      - --oidc-extra-scope=profile
      - --oidc-extra-scope=groups
      command: kubectl
      env: null
      provideClusterInfo: false
EOT
  filename = "${path.module}/../artifacts/user.kubeconfig"
}

resource "local_file" "etcd_cluster_inventory" {
  content  = <<-EOT
all:
  vars:
    ansible_ssh_user: ubuntu
    ansible_ssh_extra_args: "-o StrictHostKeyChecking=no"
    ansible_ssh_private_key_file: artifacts/id_${lower(local.platform_ssh_algorithm.algorithm)}

    kubernetes_ingress:
%{~for ingress, _ in local.platform_components.kubernetes.ingresses}
      ${ingress}:
        ip_address: "${exoscale_nlb.ingress[ingress].ip_address}"
%{endfor}
    kubernetes_apiserver_url: ${module.kubernetes_control_plane.url}
    kubernetes_control_plane_ip_address: ${data.exoscale_nlb.endpoint.ip_address}
    kubernetes_control_plane_instance_ip_address:
%{~for instance in module.kubernetes_control_plane.instances}
    - ${instance.public_ip_address~}
%{endfor}
  children:
    etcd:
      hosts:
%{~for instance in module.etcd_cluster.instances}
        ${instance.name}:
          ansible_host: ${instance.public_ip_address~}
%{endfor}
    kube-control-plane:
      hosts:
%{~for instance in module.kubernetes_control_plane.instances}
        ${instance.name}:
          ansible_host: ${instance.public_ip_address~}
%{endfor}
EOT
  filename = "${path.module}/../artifacts/kubernetes-inventory.yml"
}
