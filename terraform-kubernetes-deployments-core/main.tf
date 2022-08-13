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
      "${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" => manifest
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
      "ingress:namespace"        = "ingress-nginx-${name}"
      "ingress:class_suffix"     = name
      "ingress:node_label_name"  = split("=", ingress.label)[0]
      "ingress:node_label_value" = split("=", ingress.label)[1]
      "ingress:node_taint_name"  = split("=", ingress.label)[0]
      "ingress:node_taint_value" = split("=", ingress.label)[1]
      "ingress:domain"           = try(ingress.domain, "")
      "cert-manager:namespace"   = try(local.platform_components.kubernetes.deployments.bootstrap.cert-manager.namespace, "")
    })
  }

  ingress_manifests = merge(concat([
    for name, ingress in local.platform_components.kubernetes.ingresses : [
      merge([
        for _, deployment in ingress.deployments : {
          for manifest in split("\n---\n", file("manifests/${deployment}/${local.platform_components.kubernetes.deployments.ingress[deployment].version}/manifests.yaml")) :
          "ingress-${name}(${deployment})|${yamldecode(manifest)["apiVersion"]}.${yamldecode(manifest)["kind"]}|${yamldecode(manifest)["metadata"]["name"]}" => {
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

# Deployments: bootstrap components

resource "kubernetes_manifest" "manifest" {
  for_each = local.core_manifests

  manifest = yamldecode(join("\n", [
    for line in split("\n", each.value) :
    format(replace(replace(line, "%", "%%"), "/${local.deployment_variables_regex}/", "%s"), [
      for value in flatten(regexall(local.deployment_variables_regex, line)) : lookup(local.deployment_variables, value)
    ]...)
  ]))

  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    yamldecode(each.value)["kind"] == "Job" ? ["spec.template.metadata.labels"] : [],
  )
}

# Deployments: ingresses

resource "kubernetes_manifest" "ingress" {
  for_each = local.ingress_manifests

  manifest = yamldecode(join("\n", [
    for line in split("\n", each.value.manifest) :
    format(replace(replace(line, "%", "%%"), "/${local.ingress_variables_regex[each.value.ingress]}/", "%s"), [
      for value in flatten(regexall(local.ingress_variables_regex[each.value.ingress], line)) : lookup(local.ingress_variables[each.value.ingress], value)
    ]...)
  ]))

  computed_fields = concat(
    ["metadata.annotations", "metadata.labels"],
    yamldecode(each.value.manifest)["kind"] == "Job" ? ["spec.template.metadata.labels"] : [],
  )
}

# Vault <---> Kubernetes

resource "kubernetes_secret" "vault" {
  depends_on = [kubernetes_manifest.manifest]
  for_each = merge(
    can(local.platform_components.kubernetes.deployments.bootstrap["cert-manager"]) &&
    can(local.platform_components.kubernetes.deployments.core["metrics-server"]) ? {
      "metrics-server" = {
        service-account = "metrics-server"
        namespace       = "kube-system"
      }
    } : {},
    can(local.platform_components.kubernetes.deployments.core["vault-agent-injector"]) ? {
      "vault-agent-injector" = {
        service-account = "vault"
        namespace       = "vault-agent-injector"
      }
    } : {}
  )

  metadata {
    name      = "cert-manager-${each.key}-token"
    namespace = each.value.namespace
    annotations = {
      "kubernetes.io/service-account.name" = each.value.service-account
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Workaround to access data.token from the secret
data "kubernetes_secret" "vault" {
  for_each = kubernetes_secret.vault

  metadata {
    name      = each.value.metadata[0].name
    namespace = each.value.metadata[0].namespace
  }
}

resource "vault_auth_backend" "kubernetes" {
  for_each = toset(concat(
    can(local.platform_components.kubernetes.deployments.bootstrap["cert-manager"]) ? [
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
    can(local.platform_components.kubernetes.deployments.bootstrap["cert-manager"]) &&
    can(local.platform_components.kubernetes.deployments.core["metrics-server"]) ? {
      "metrics-server" = {
        backend = "cert-manager"
        token   = data.kubernetes_secret.vault["metrics-server"].data["token"]
      }
    } : {},
    can(local.platform_components.kubernetes.deployments.core["vault-agent-injector"]) ? {
      "vault-agent-injector" = {
        backend = "vault-agent-injector"
        token   = data.kubernetes_secret.vault["vault-agent-injector"].data["token"]
      }
    } : {}
  )

  backend                = vault_auth_backend.kubernetes[each.value["backend"]].path
  kubernetes_host        = local.kubernetes.apiserver_url
  kubernetes_ca_cert     = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  token_reviewer_jwt     = each.value["token"] //kubernetes_secret.vault_token[each.key].data["token"]
  issuer                 = "kubernetes.default.svc.${local.platform_components.kubernetes.cluster_domain}"
  disable_iss_validation = true
}

resource "vault_kubernetes_auth_backend_role" "roles" {
  for_each = merge(
    can(local.platform_components.kubernetes.deployments.core["metrics-server"]) ? { "metrics-server" = {
      backend         = "cert-manager"
      namespace       = try(local.platform_components.kubernetes.deployments.core["metrics-server"].namespace, null)
      service_account = "metrics-server"
    } } : {},
  )

  backend                          = vault_auth_backend.kubernetes[each.value["backend"]].path
  role_name                        = each.key
  bound_service_account_namespaces = [each.value["namespace"]]
  bound_service_account_names      = [try(each.value["service_account"], each.key)]
  token_policies                   = ["default", try(each.value["policy"], "platform-kubernetes-${each.key}")]
  token_ttl                        = 3600
}