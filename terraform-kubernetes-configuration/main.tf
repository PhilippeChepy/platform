locals {
  # namespaces = toset(concat([
  #   for _, deployment in merge(
  #     local.platform_components.kubernetes.deployments.bootstrap,
  #     local.platform_components.kubernetes.deployments.core
  #   ) : deployment.namespace
  #   if deployment.namespace != "kube-system"
  #   ], [
  #   for name, ingress in local.platform_components.kubernetes.ingresses : "ingress-nginx-${name}"
  # ]))

  # # This local is an array of yaml decoded manifests
  # # - manifests.yaml of each deployment is split by resource (a single yaml document is split by "---" delimiter)
  # # - the result is transformed to a native HCL yaml structure using yamldecode()
  # # - this result is stored in the manifest array, unless manifest is empty
  # bootstrap_manifests = concat([
  #   for name, deployment in local.platform_components.kubernetes.deployments.bootstrap : [
  #     for manifest in split("\n---\n",
  #       try(deployment.templated, true) ?
  #       templatefile("manifests/${name}/${deployment.version}/manifests.yaml", local.deployment_variables) :
  #       file("manifests/${name}/${deployment.version}/manifests.yaml")
  #     ) :
  #     yamldecode(manifest)
  #     if manifest != ""
  #   ]
  # ]...)

  # # Here we transform the `bootstrap_manifests` local into a nonsensitive data set using `try(nonsensitive(X), X)` construction.
  # # Each manifest is placed into a map, indexed by a unique identifier.
  # #
  # # QUIRK: some manifests can be considered sensitive. That's why we use the `try(nonsensitive(X), X)` construction,
  # # in order to enforce non-sensitiveness of the variable.
  # bootstrap_resources = {
  #   for resource in try(nonsensitive(local.bootstrap_manifests), local.bootstrap_manifests) :
  #   "apiVersion=${resource.apiVersion},${try("namespace=${resource.metadata.namespace},", "")}kind=${resource.kind},name=${resource.metadata.name}" => resource
  # }
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

# Deployments

resource "null_resource" "bootstrap_namespace" {
  for_each = toset(["argocd", "cert-manager"])

  provisioner "local-exec" {
    when        = create
    command     = "kubectl create namespace ${each.key} --dry-run=client -o yaml |kubectl apply --filename=-"
    environment = { KUBECONFIG = "../artifacts/admin.kubeconfig" }
  }

  // No provisioner with `when = destroy` this is resource is only for bootstrap purpose
}

resource "null_resource" "bootstrap_deployment" {
  depends_on = [null_resource.bootstrap_namespace]
  for_each   = {
    cilium  = { namespace = "kube-system" }
    coredns = { namespace = "kube-system" }
    argocd  = { namespace = "argocd" }
    # konnectivity-agent = { namespace = "kube-system" }
  }

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
cat <<'EOF' | kubectl apply --namespace=${each.value.namespace} --filename=-
${sensitive(templatefile("manifests/${each.key}/manifests.yaml", local.bootstrap_deployment_variable))}
EOF
EOT
    environment = { KUBECONFIG = "../artifacts/admin.kubeconfig" }
  }

  // No provisioner with `when = destroy` this is resource is only for bootstrap purpose
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
  path = "kubernetes2" # TODO
}

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on         = [vault_auth_backend.kubernetes]
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = "https://${local.kubernetes.control_plane_ip_address}:6443" // module.kubernetes_control_plane.url
  kubernetes_ca_cert = data.vault_generic_secret.kubernetes["control-plane-ca"].data["ca_chain"]
  pem_keys           = [chomp(data.vault_generic_secret.kubernetes["service-account-key"].data["public_key"])]
}

resource "vault_kubernetes_auth_backend_role" "roles" {
  depends_on = [vault_auth_backend.kubernetes]
  for_each = {
    cert-manager = { namespace = "cert-manager", service-account = "cert-manager" },
    argocd       = { namespace = "argocd", service-account = "argocd" }
  }
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = each.key
  bound_service_account_namespaces = [each.value.namespace]
  bound_service_account_names      = [each.value.service-account]
  token_policies                   = ["default", "platform-deployment-${each.key}"]
  token_ttl                        = 3600
}
