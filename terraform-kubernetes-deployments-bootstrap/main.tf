locals {
  # Control plane CAs & deployment properties
  deployment_variables = {
    "platform_domain"                       = local.platform_domain
    "kubernetes_aggregationlayer_ca_cert"   = base64encode(data.vault_generic_secret.kubernetes["aggregation-layer-ca"].data["ca_chain"])
    "kubernetes_kubelet_ca_cert"            = base64encode(data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"])
    "kubernetes_apiserver_ipv4"             = local.kubernetes.control_plane_ip_address
    "kubernetes_cluster_domain"             = local.platform_components.kubernetes.cluster_domain
    "kubernetes_pod_cidr_ipv4"              = local.platform_components.kubernetes.pod_cidr_ipv4
    "kubernetes_pod_cidr_ipv6"              = local.platform_components.kubernetes.pod_cidr_ipv6
    "kubernetes_dns_service_ipv4"           = local.platform_components.kubernetes.dns_service_ipv4
    "kubernetes_dns_service_ipv6"           = local.platform_components.kubernetes.dns_service_ipv6
    "kubernetes_service_cidr_ipv4"          = local.platform_components.kubernetes.service_cidr_ipv4
    "kubernetes_service_cidr_ipv6"          = local.platform_components.kubernetes.service_cidr_ipv6
    "kubernetes_proxy_server_0_ipv4"        = local.kubernetes.control_plane_instance_ip_address[0]
    "kubernetes_proxy_server_1_ipv4"        = local.kubernetes.control_plane_instance_ip_address[1]
    "vault_cluster_url"                     = local.vault.url
    "vault_cluster_ipv4"                    = local.vault.ip_address
    "vault_cluster_ca_cert"                 = base64encode(data.local_file.root_ca_certificate_pem.content)
    "vault_path_pki_sign_aggregation_layer" = local.pki.pki_sign_aggregation_layer

    # Colision between actual manifest content and the Terraform templating syntax
    "BIN_PATH" = "$${BIN_PATH}" # Cilium manifests
  }

  namespaces = toset(concat([
    for _, deployment in merge(
      local.platform_components.kubernetes.deployments.bootstrap,
      local.platform_components.kubernetes.deployments.core
    ) : deployment.namespace
    if deployment.namespace != "kube-system"
    ], [
    for name, ingress in local.platform_components.kubernetes.ingresses : "ingress-nginx-${name}"
  ]))

  # This local is an array of yaml decoded manifests
  # - manifests.yaml of each deployment is split by resource (a single yaml document is split by "---" delimiter)
  # - the result is transformed to a native HCL yaml structure using yamldecode()
  # - this result is stored in the manifest array, unless manifest is empty
  bootstrap_manifests = concat([
    for name, deployment in local.platform_components.kubernetes.deployments.bootstrap : [
      for manifest in split("\n---\n",
        try(deployment.templated, true) ?
        templatefile("manifests/${name}/${deployment.version}/manifests.yaml", local.deployment_variables) :
        file("manifests/${name}/${deployment.version}/manifests.yaml")
      ) :
      yamldecode(manifest)
      if manifest != ""
    ]
  ]...)

  # Here we transform the `bootstrap_manifests` local into a nonsensitive data set using `try(nonsensitive(X), X)` construction.
  # Each manifest is placed into a map, indexed by a unique identifier.
  #
  # QUIRK: some manifests can be considered sensitive. That's why we use the `try(nonsensitive(X), X)` construction,
  # in order to enforce non-sensitiveness of the variable.
  bootstrap_resources = {
    for resource in try(nonsensitive(local.bootstrap_manifests), local.bootstrap_manifests) :
    "apiVersion=${resource.apiVersion},${try("namespace=${resource.metadata.namespace},", "")}kind=${resource.kind},name=${resource.metadata.name}" => resource
  }
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
    service-account-key  = "kv/platform/kubernetes/service-account"
  }

  path = each.value
}

# Deployments

resource "kubernetes_namespace" "namespace" {
  for_each = local.namespaces

  metadata {
    name = each.value
  }
}

resource "kubernetes_manifest" "manifest" {
  depends_on = [kubernetes_namespace.namespace]
  for_each   = local.bootstrap_resources

  manifest = each.value
  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    each.value.kind == "Job" ? ["spec.template.metadata.labels"] : [],
  )
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
    {
      for name in ["core"] :
      "certificate-${name}" => {
        namespace       = "cert-manager"
        service-account = "cert-manager-deployment-${name}"
      }
    },
    concat([], [
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
  kubernetes_host    = "https://${local.kubernetes.control_plane_ip_address}:6443" // module.kubernetes_control_plane.url
  kubernetes_ca_cert = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  pem_keys           = [chomp(data.vault_generic_secret.kubernetes["service-account-key"].data["public_key"])]
  # token_reviewer_jwt = data.kubernetes_secret_v1.vault.data["token"]
  
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
