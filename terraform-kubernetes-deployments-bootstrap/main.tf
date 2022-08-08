locals {
  variables_regex = "\\$(${join("|", keys(local.deployment_variables))})\\$"

  # Control plane CAs & deployment properties
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
    "vault:auth_path"                       = "auth/kubernetes/vault-agent-injector"
    "vault:path_pki_sign:aggregation_layer" = local.pki.pki_sign_aggregation_layer
  }

  namespaces = toset(concat([
    for _, deployment in local.platform_components.kubernetes.deployments.bootstrap : deployment.namespace
    if deployment.namespace != "kube-system"
    ], [
    for _, deployment in local.platform_components.kubernetes.deployments.core : deployment.namespace
    if deployment.namespace != "kube-system"
    ], [
    for name, ingress in local.platform_components.kubernetes.ingresses : "ingress-nginx-${name}"
  ]))

  bootstrap_manifests = merge([
    for name, deployment in local.platform_components.kubernetes.deployments.bootstrap : {
      for manifest in split("\n---\n", file("manifests/${name}/${deployment.version}/manifests.yaml")) :
      "${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" => manifest
    }
  ]...)
}

data "vault_generic_secret" "kubernetes" {
  for_each = {
    control-plane-ca     = "pki/platform/kubernetes/control-plane/cert/ca_chain"
    kubelet-ca           = "pki/platform/kubernetes/kubelet/cert/ca_chain"
    aggregation-layer-ca = "pki/platform/kubernetes/aggregation-layer/cert/ca_chain"
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
  for_each   = local.bootstrap_manifests

  manifest = yamldecode(join("\n", [
    for line in split("\n", each.value) :
    format(replace(replace(line, "%", "%%"), "/${local.variables_regex}/", "%s"), [
      for value in flatten(regexall(local.variables_regex, line)) : lookup(local.deployment_variables, value)
    ]...)
  ]))

  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    yamldecode(each.value)["kind"] == "Job" ? ["spec.template.metadata.labels"] : [],
  )
}
