locals {
  # Control plane CAs & deployment properties
  deployment_variables_regex = "\\$(${join("|", keys(local.deployment_variables))})\\$"

  deployment_variables = {
    "provider:zone"                         = local.platform_zone
    "kubernetes:apiserver_ca_cert"          = base64encode(data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"])
    "kubernetes:aggregationlayer_ca_cert"   = base64encode(data.vault_generic_secret.kubernetes["aggregation-layer-ca"].data["ca_chain"])
    "kubernetes:kubelet_ca_cert"            = base64encode(data.vault_generic_secret.kubernetes["kubelet-ca"].data["ca_chain"])
    "kubernetes:apiserver_service_ipv4"     = local.platform_components.kubernetes.apiserver_service_ipv4
    "kubernetes:apiserver_service_ipv6"     = local.platform_components.kubernetes.apiserver_service_ipv6
    "kubernetes:apiserver_ipv4"             = local.kubernetes.control_plane_ip_address
    "kubernetes:cluster_domain"             = local.platform_components.kubernetes.cluster_domain
    "kubernetes:pod_cidr_ipv4"              = local.platform_components.kubernetes.pod_cidr_ipv4
    "kubernetes:pod_cidr_ipv6"              = local.platform_components.kubernetes.pod_cidr_ipv6
    "kubernetes:dns_service_ipv4"           = local.platform_components.kubernetes.dns_service_ipv4
    "kubernetes:dns_service_ipv6"           = local.platform_components.kubernetes.dns_service_ipv6 // XXX: implement it in addition to ipv4
    "kubernetes:service_cidr_ipv4"          = local.platform_components.kubernetes.service_cidr_ipv4
    "kubernetes:service_cidr_ipv6"          = local.platform_components.kubernetes.service_cidr_ipv6
    "kubernetes:proxy_server_0_ipv4"        = local.kubernetes.control_plane_instance_ip_address[0]
    "kubernetes:proxy_server_1_ipv4"        = local.kubernetes.control_plane_instance_ip_address[1]
    "vault:cluster_addr"                    = local.vault.url
    "vault:cluster_ca_cert"                 = base64encode(data.local_file.root_ca_certificate_pem.content)
    "vault:path_pki_sign:aggregation_layer" = local.pki.pki_sign_aggregation_layer
  }

  core_manifests = merge([
    for name, deployment in local.platform_components.kubernetes.deployments.core : {
      for manifest in split("\n---\n", file("manifests/${name}/${deployment.version}/manifests.yaml")) :
      "${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" =>
      yamldecode(join("\n", [
        for line in split("\n", manifest) :
        format(replace(replace(line, "%", "%%"), "/${local.deployment_variables_regex}/", "%s"), [
          for value in flatten(regexall(local.deployment_variables_regex, line)) : lookup(local.deployment_variables, value)
        ]...)
      ]))
      if manifest != ""
    }
  ]...)

  # Ingress-reloated workloads

  ingress_variables_regex = {
    for name, _ in local.platform_components.kubernetes.ingresses : name =>
    "\\$(${join("|", keys(local.ingress_variables[name]))})\\$"
  }

  ingress_variables = {
    for name, ingress in local.platform_components.kubernetes.ingresses :
    name => merge(local.deployment_variables, {
      "ingress:namespace"          = "ingress-nginx-${name}"
      "ingress:class_suffix"       = name
      "ingress:node_label_name"    = split("=", ingress.label)[0]
      "ingress:node_label_value"   = split("=", ingress.label)[1]
      "ingress:node_taint_name"    = split("=", ingress.label)[0]
      "ingress:node_taint_value"   = split("=", ingress.label)[1]
      "ingress:domain"             = try(ingress.domain, "")
      "cert-manager:namespace"     = try(local.platform_components.kubernetes.deployments.bootstrap.cert-manager.namespace, "")
      "cert-manager:wildcard_name" = "${replace(try(ingress.domain, ""), ".", "-")}"
      "external-dns:namespace"     = "ingress-nginx-${name}"
    })
  }

  ingress_manifests = merge(
    # Generic ingress-related deployment
    merge(concat([
      for name, ingress in local.platform_components.kubernetes.ingresses : [
        merge([
          for _, deployment in ingress.deployments : {
            for manifest in split("\n---\n", file("manifests/${deployment}/${local.platform_components.kubernetes.deployments.ingress[deployment].version}/manifests.yaml")) :
            "ingress-${name}(${deployment})|${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" =>
            yamldecode(join("\n", [
              for line in split("\n", manifest) :
              format(replace(replace(line, "%", "%%"), "/${local.ingress_variables_regex[name]}/", "%s"), [
                for value in flatten(regexall(local.ingress_variables_regex[name], line)) : lookup(local.ingress_variables[name], value)
              ]...)
            ]))
            if manifest != "" && try(local.platform_components.kubernetes.deployments.ingress[deployment].provider, null) == null
          }
        ]...)
      ]
    ]...)...),
    # Cloudflare specific deployments
    merge(concat([
      for name, ingress in local.platform_components.kubernetes.ingresses : [
        merge([
          for _, deployment in ingress.deployments : {
            for manifest in split("\n---\n", file("manifests/${deployment}/${local.platform_components.kubernetes.deployments.ingress[deployment].version}/manifests.yaml")) :
            "ingress-${name}(${deployment})|${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" =>
            yamldecode(join("\n", [
              for line in split("\n", manifest) :
              format(replace(replace(line, "%", "%%"), "/${local.ingress_variables_regex[name]}/", "%s"), [
                for value in flatten(regexall(local.ingress_variables_regex[name], line)) : lookup(local.ingress_variables[name], value)
              ]...)
            ]))
            if manifest != "" && contains(["cloudflare", "any"], try(local.platform_components.kubernetes.deployments.ingress[deployment].provider, ""))
          }
        ]...)
      ]
    ]...)...)
  )

  manifests_service_accounts = {
    for name, manifest in merge(local.core_manifests, local.ingress_manifests) : name => {
      manifest        = manifest
      computed_fields = ["metadata.annotations", "metadata.labels"]
    }
    # QUIRK: manifest can be considered sensitive. "try(nonsensitive(manifest), manifest)" enforce non-sensitiveness of the manifest variable
    if try(nonsensitive(manifest), manifest).kind == "ServiceAccount"
  }

  manifests = merge({
    for name, manifest in merge(local.core_manifests, local.ingress_manifests) : name => {
      manifest        = manifest # try(nonsensitive(manifest), manifest)
      computed_fields = concat(["metadata.annotations", "metadata.labels"], manifest.kind == "Job" ? ["spec.template.metadata.labels"] : [])
    }
    # QUIRK: manifest can be considered sensitive. "try(nonsensitive(manifest), manifest)" enforce non-sensitiveness of the manifest variable
    if try(nonsensitive(manifest), manifest).kind != "ServiceAccount"
  })
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
  }

  path = each.value
}

# Deployments: only ServiceAccount

resource "kubernetes_manifest" "manifest_service_accounts" {
  for_each = local.manifests_service_accounts

  manifest        = each.value.manifest
  computed_fields = each.value.computed_fields
}

# Deployments: anything else except ServiceAccounts

resource "kubernetes_manifest" "manifest" {
  for_each   = local.manifests
  depends_on = [kubernetes_manifest.manifest_service_accounts]

  manifest        = each.value.manifest
  computed_fields = each.value.computed_fields
}
