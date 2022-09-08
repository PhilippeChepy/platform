locals {

  platform_ingress_class = one([
    for name, ingress in local.platform_components.kubernetes.ingresses : "nginx-${name}"
    if try(ingress.domain, null) != null && trimsuffix(".${local.platform_domain}", ".${try(ingress.domain, "")}") != ".${local.platform_domain}"
  ])

  # Control plane CAs & deployment properties
  deployment_variables = merge({
    "platform_domain"                       = local.platform_domain
    "kubernetes_aggregationlayer_ca_cert"   = base64encode(data.vault_generic_secret.kubernetes["aggregation-layer-ca"].data["ca_chain"])
    "kubernetes_kubelet_ca_cert"            = base64encode(data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"])
    "kubernetes_apiserver_ipv4"             = local.kubernetes.control_plane_ip_address
    "kubernetes_cluster_domain"             = local.platform_components.kubernetes.cluster_domain
    "kubernetes_pod_cidr_ipv4"              = local.platform_components.kubernetes.pod_cidr_ipv4
    "kubernetes_pod_cidr_ipv6"              = local.platform_components.kubernetes.pod_cidr_ipv6
    "kubernetes_dns_service_ipv4"           = local.platform_components.kubernetes.dns_service_ipv4
    "kubernetes_dns_service_ipv6"           = local.platform_components.kubernetes.dns_service_ipv6
    "kubernetes_proxy_server_0_ipv4"        = local.kubernetes.control_plane_instance_ip_address[0]
    "kubernetes_proxy_server_1_ipv4"        = local.kubernetes.control_plane_instance_ip_address[1]
    "vault_cluster_addr"                    = local.vault.url
    "vault_cluster_ca_cert"                 = base64encode(data.local_file.root_ca_certificate_pem.content)
    "vault_path_pki_sign_aggregation_layer" = local.pki.pki_sign_aggregation_layer
    "vault_path_pki_sign_dex"               = local.pki.pki_sign_dex
    "dex_issuer_domain"                     = "dex.${local.platform_domain}"
    "dex_ingress_class_name"                = local.platform_ingress_class
    "oidc_issuer"                           = "https://vault.${local.platform_domain}:8200/v1/identity/oidc/provider/default"
    "oidc_provider_url"                     = "https://dex.${local.platform_domain}"
    },
    local.platform_authentication["provider"] == "vault" ? {
      "oidc_client_id"     = data.vault_generic_secret.vault_dex[0].data["client_id"]
      "oidc_client_secret" = data.vault_generic_secret.vault_dex[0].data["client_secret"]
      } : {
  })

  # Ingress-related workloads
  ingress_variables = {
    for name, ingress in local.platform_components.kubernetes.ingresses :
    name => merge(local.deployment_variables, {
      "ingress_namespace"          = "ingress-nginx-${name}"
      "ingress_class_suffix"       = name
      "ingress_node_label_name"    = split("=", ingress.label)[0]
      "ingress_node_label_value"   = split("=", ingress.label)[1]
      "ingress_node_taint_name"    = split("=", ingress.label)[0]
      "ingress_node_taint_value"   = split("=", ingress.label)[1]
      "ingress_domain"             = try(ingress.domain, "")
      "ingress_default_cert"       = "${replace(try(ingress.domain, ""), ".", "-")}-wildcard-cert" # TODO: implement default TLS cert if not provided by DNS01 integration
      "ingress_loadbalancer_ip"    = local.kubernetes.ingress[name].ip_address
      "cert_manager_wildcard_name" = "${replace(try(ingress.domain, ""), ".", "-")}"
      "external_dns_namespace"     = "ingress-nginx-${name}"
    })
  }

  # `*_manifests` locals are arrays of yaml decoded manifests
  # - manifests.yaml of each deployment is split by resource (a single yaml document is split by "---" delimiter)
  # - the result is transformed to a native HCL yaml structure using yamldecode()
  # - this result is stored in the manifest array, unless manifest is empty

  core_manifests = concat([
    for name, deployment in local.platform_components.kubernetes.deployments.core : [
      for manifest in split("\n---\n", templatefile("manifests/${name}/${deployment.version}/manifests.yaml", local.deployment_variables)) :
      yamldecode(manifest)
      if manifest != ""
    ]
  ]...)

  ingress_manifests = concat([], [
    for name, ingress in local.platform_components.kubernetes.ingresses :
    concat([
      for _, deployment in ingress.deployments : [
        for manifest in split("\n---\n", templatefile("manifests/${deployment}/${local.platform_components.kubernetes.deployments.ingress[deployment].version}/manifests.yaml", local.ingress_variables[name])) :
        yamldecode(manifest)
        if manifest != "" && (
          try(local.platform_components.kubernetes.deployments.ingress[deployment].provider, null) == null ||
          contains(concat(try(ingress.integration, null) != null ? [ingress.integration] : [], ["any"]), try(local.platform_components.kubernetes.deployments.ingress[deployment].provider, ""))
        )
      ]
    ]...)
  ]...)

  all_manifests = concat(local.core_manifests, local.ingress_manifests)

  # Here we transform the `all_manifests` local into a nonsensitive data set using `try(nonsensitive(X), X)` construction.
  # Each manifest is placed into a map, indexed by a unique identifier.
  #
  # QUIRK: some manifests can be considered sensitive. That's why we use the `try(nonsensitive(X), X)` construction,
  # in order to enforce non-sensitiveness of the variable.
  all_resources = {
    for resource in try(nonsensitive(local.all_manifests), local.all_manifests) :
    "apiVersion=${resource.apiVersion},${try("namespace=${resource.metadata.namespace},", "")}kind=${resource.kind},name=${resource.metadata.name}" => resource
  }
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
  }

  path = each.value
}

data "vault_generic_secret" "vault_dex" {
  count = local.platform_authentication["provider"] == "vault" ? 1 : 0
  path  = "identity/oidc/client/dex"
}

# Deployments: only ServiceAccount

resource "kubernetes_manifest" "manifest_service_accounts" {
  for_each = { for name, manifest in local.all_resources : name => manifest if manifest.kind == "ServiceAccount" }

  manifest        = each.value
  computed_fields = concat(["metadata.annotations", "metadata.labels"])
}

# Deployments: anything else except ServiceAccounts

resource "kubernetes_manifest" "manifest" {
  for_each   = { for name, manifest in local.all_resources : name => manifest if manifest.kind != "ServiceAccount" }
  depends_on = [kubernetes_manifest.manifest_service_accounts]

  manifest = each.value
  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    each.value.kind == "Job" ? ["spec.template.metadata.labels"] : [],
  )
}
