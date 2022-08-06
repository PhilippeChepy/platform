locals {
  domains = [
    for _, ingress in local.platform_components.kubernetes.ingresses : try(ingress.domain, null)
    if try(ingress.domain, null) != null
  ]
}

data "cloudflare_api_token_permission_groups" "all" {
}

data "cloudflare_zone" "zone" {
  for_each = toset(local.domains)
  name     = each.key
}

resource "cloudflare_api_token" "api_key" {
  name = local.platform_name

  policy {
    permission_groups = [
      data.cloudflare_api_token_permission_groups.all.permissions["DNS Write"],
      data.cloudflare_api_token_permission_groups.all.permissions["Zone Read"],
    ]
    resources = {
      for zone in local.domains :
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.zone[zone].zone_id}" => "*"
    }
  }
}

locals {

  # Ingress-reloated workloads

  ingress_variables_regex = {
    for name, _ in local.platform_components.kubernetes.ingresses : name =>
    "\\$(${join("|", keys(local.ingress_variables[name]))})\\$"
  }

  ingress_variables = {
    for name, ingress in local.platform_components.kubernetes.ingresses :
    name => {
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
      "vault:auth_path"                       = "auth/kubernetes/vault-agent-injector"
      "vault:path_pki_sign:aggregation_layer" = local.pki.pki_sign_aggregation_layer
      "ingress:namespace"                     = "ingress-nginx-${name}"
      "ingress:class_suffix"                  = name
      "ingress:node_label_name"               = split("=", ingress.label)[0]
      "ingress:node_label_value"              = split("=", ingress.label)[1]
      "ingress:node_taint_name"               = split("=", ingress.label)[0]
      "ingress:node_taint_value"              = split("=", ingress.label)[1]
      "ingress:domain"                        = try(ingress.domain, "")
      "cert-manager:namespace"                = try(local.platform_components.kubernetes.deployments.bootstrap.cert-manager.namespace, "")
      "cert-manager:cloudflare_token"         = cloudflare_api_token.api_key.value
      "cert-manager:wildcard_name"            = "${replace(try(ingress.domain, ""), ".", "-")}"
      "external-dns:namespace"                = "ingress-nginx-${name}"
      "external-dns:cloudflare_token"         = base64encode(cloudflare_api_token.api_key.value)
    }
  }

  ingress_manifests = merge(concat([
    for name, ingress in local.platform_components.kubernetes.ingresses : [
      merge([
        for _, deployment in try(ingress.deployments-cloudflare, []) : {
          for manifest in split("---", file("manifests/${deployment}/${local.platform_components.kubernetes.deployments.ingress-cloudflare[deployment].version}/manifests.yaml")) :
          "ingress-${name}|${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" => {
            ingress  = name,
            manifest = manifest
          }
          if manifest != ""
        }
      ]...)
    ]
  ]...)...)
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
  }

  path = each.value
}

# Deployments: ingresses

resource "kubernetes_manifest" "ingress" {
  for_each = local.ingress_manifests
  depends_on = [ cloudflare_api_token.api_key ]

  manifest = yamldecode(join("\n", [
    for line in split("\n", each.value.manifest) :
    format(replace(line, "/${local.ingress_variables_regex[each.value.ingress]}/", "%s"), [
      for value in flatten(regexall(local.ingress_variables_regex[each.value.ingress], line)) : lookup(local.ingress_variables[each.value.ingress], value)
    ]...)
  ]))

  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    yamldecode(each.value.manifest)["kind"] == "Job" ? ["spec.template.metadata.labels"] : [],
    yamldecode(each.value.manifest)["kind"] == "Secret" ? ["data", "stringData"] : [],
  )
}
