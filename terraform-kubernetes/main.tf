locals {
  # Settings for Vault clients

  vault_settings = {
    url                = local.vault.url
    cluster_name       = "${local.platform_name}-vault"
    ca_certificate_pem = data.local_file.root_ca_certificate_pem.content
    healthcheck_url    = "${local.vault.url}/v1/sys/health"
  }

  # Settings for Kubernetes clients

  kubelet_bootstrap_token = join(".", [
    data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"],
    data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"],
  ])

  kubernetes_settings = {
    apiserver_ip_address         = data.exoscale_nlb.endpoint.ip_address
    apiserver_url                = module.kubernetes_control_plane.url
    cluster_domain               = local.platform_components.kubernetes.cluster_domain
    controlplane_ca_pem          = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
    dns_service_ipv4             = local.platform_components.kubernetes.dns_service_ipv4
    dns_service_ipv6             = local.platform_components.kubernetes.dns_service_ipv6
    kubelet_authentication_token = local.kubelet_bootstrap_token
    kubelet_ca_pem               = data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"]
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
    service-account-key  = "kv/platform/kubernetes/service-account"
  }

  path = each.value
}

data "vault_generic_secret" "cloudflare" {
  for_each = toset([
    for ingress_name, ingress in local.platform_components.kubernetes.ingresses : ingress_name
    if try(ingress.integration, "") == "cloudflare"
  ])

  path = "kv/platform/cloudflare/${each.value}"
}

data "vault_generic_secret" "oidc_client_secret" {
  for_each = merge(
    local.platform_authentication["provider"] == "vault" ? {
      "dex" = "identity/oidc/client/dex"
    } : {},
    {
      "argocd" = "kv/platform/oidc/argocd"
    }
  )

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
    servers    = join(",", [for instance in module.etcd_cluster.instances: "https://${instance.public_ip_address}:2379"])
    ip_address = data.exoscale_nlb.endpoint.ip_address
  }

  kubernetes = {
    apiserver_service_ipv4 = local.platform_components.kubernetes.apiserver_service_ipv4
    bootstrap_token_id     = data.vault_generic_secret.kubernetes["bootstrap-token"].data["id"]
    bootstrap_token_secret = data.vault_generic_secret.kubernetes["bootstrap-token"].data["secret"]
    cluster_domain         = local.platform_components.kubernetes.cluster_domain
    pod_cidr_ipv4          = local.platform_components.kubernetes.pod_cidr_ipv4
    pod_cidr_ipv6          = local.platform_components.kubernetes.pod_cidr_ipv6
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
      size          = 3
      instance_type = "standard.small"
      root_size     = 10
    }
    },
    local.platform_components.kubernetes.storage.enabled ? {
      "ceph-mon" = {
        size          = 3
        instance_type = "standard.small"
        root_size     = 10
        data_size     = 60
        labels        = { "${local.platform_domain}/role" = "monitor" }
        taints        = { "${local.platform_domain}/role" = { value = "monitor", effect = "NoSchedule" } }
      },
      "ceph-osd" = {
        size          = 3
        instance_type = "standard.small"
        root_size     = 10
        data_size     = 90
        labels        = { "${local.platform_domain}/role" = "data" }
        taints        = { "${local.platform_domain}/role" = { value = "data", effect = "NoSchedule" } }
      },
      "ceph-mds" = {
        size          = 2
        instance_type = "standard.small"
        root_size     = 10
        data_size     = 1
        labels        = { "${local.platform_domain}/role" = "metadata" }
        taints        = { "${local.platform_domain}/role" = { value = "metadata", effect = "NoSchedule" } }
      }
    } : {},
    {
      for name, ingress in local.platform_components.kubernetes.ingresses :
      "ingress-${name}" => {
        size                 = ingress.pool_size
        instance_type        = "standard.tiny"
        root_size            = 10
        labels               = { "${local.platform_domain}/ingress" = name }
        taints               = { "${local.platform_domain}/ingress" = { value = name, effect = "NoSchedule" } }
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
  security_group_rules = startswith(each.key, "ingress-") ? local.ingress_security_group_rules : {}
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

  root_size = try(each.value.root_size, 10)
  data_size = try(each.value.data_size, 0)
}

# Deployments

resource "null_resource" "bootstrap_namespace" {
  for_each   = toset(["argocd", "cert-manager"])

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "while ! nc -z -w5 ${data.exoscale_nlb.endpoint.ip_address} 6443; do echo \"Waiting for control-plane availability\"; sleep 5; done"
  }

  provisioner "local-exec" {
    when        = create
    command     = "kubectl create namespace ${each.key} --dry-run=client -o yaml |kubectl apply --filename=-"
    environment = { KUBECONFIG = "../artifacts/admin.kubeconfig" }
  }

  # No provisioner with `when = destroy` this is resource is only for bootstrap purpose
}

resource "null_resource" "bootstrap_deployment" {
  depends_on = [null_resource.bootstrap_namespace]
  for_each = {
    cilium  = { namespace = "kube-system" }
    coredns = { namespace = "kube-system" }
    argocd  = { namespace = "argocd" }
    # konnectivity-agent = { namespace = "kube-system" }
  }

  provisioner "local-exec" {
    when        = create
    command     = <<-EOT
cat <<'EOF' | kubectl apply --namespace=${each.value.namespace} --filename=-
${sensitive(templatefile("manifests/${each.key}/manifests.yaml", local.bootstrap_deployment_variable))}
EOF
EOT
    environment = { KUBECONFIG = "../artifacts/admin.kubeconfig" }
  }

  # No provisioner with `when = destroy` this is resource is only for bootstrap purpose
}

resource "null_resource" "root_applications" {
  depends_on = [null_resource.bootstrap_deployment]
  for_each   = toset(["argocd-core-root-application", "argocd-ingress-root-application"])

  triggers = {
    apply_command  = <<-EOT
cat <<'EOF' | kubectl apply --namespace=argocd --filename=-
${sensitive(templatefile("manifests/${each.key}/manifests.yaml", local.bootstrap_deployment_variable))}
EOF
EOT
    delete_command = <<-EOT
cat <<'EOF' | kubectl delete --namespace=argocd --filename=-
${sensitive(templatefile("manifests/${each.key}/manifests.yaml", local.bootstrap_deployment_variable))}
EOF
EOT
  }

  provisioner "local-exec" {
    when    = create
    command = self.triggers.apply_command
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.delete_command
    environment = {
      KUBECONFIG = "../artifacts/admin.kubeconfig"
    }
  }
}

# Services interactions

## Vault <---> Kubernetes deployments

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on         = [vault_auth_backend.kubernetes]
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = module.kubernetes_control_plane.url
  kubernetes_ca_cert = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  pem_keys           = [chomp(data.vault_generic_secret.kubernetes["service-account-key"].data["public_key"])]
}

resource "vault_kubernetes_auth_backend_role" "roles" {
  depends_on = [vault_auth_backend.kubernetes]
  for_each = {
    cert-manager               = { namespace = "cert-manager", service-account = "cert-manager" },
    argocd                     = { namespace = "argocd", service-account = "argocd" }
    certificate-core           = { namespace = "cert-manager", service-account = "cert-manager-deployment-core" }
    certificate-metrics-server = { namespace = "kube-system", service-account = "cert-manager-metrics-server" }
  }
  backend                          = vault_auth_backend.kubernetes.path
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
  ttl         = local.platform_tls_settings.ttl_hours.cert * 3600
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
    ansible_ssh_private_key_file: artifacts/id_${lower(local.platform_ssh_settings.algorithm)}

    kubernetes_apiserver_url: ${module.kubernetes_control_plane.url}
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
