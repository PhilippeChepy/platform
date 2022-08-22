locals {
  groups_users = transpose(merge([
    for username, user in local.platform_authentication.users: {(username) = try(user.groups, [])}
  ]...))

  namespaces = merge([
    for project_name, project in local.platform_app_namespaces : {
      for environment_name, environment in project : "${project_name}-${environment_name}" => {
        environment = environment,
        project = project
        # groups = try(environment.groups, [])
        users = toset(concat(
          try(environment.users, []),
          [for group in try(environment.groups, []): try(local.groups_users[group])]...
        ))
      }
    }
  ]...)

  namespace_users = merge([
    for name, namespace in local.namespaces : {
      for username, user in namespace.users : "${name}|${username}" => { user = username, namespace = name }
    }
  ]...)

  users_namespaces = transpose({for namespace, spec in local.namespaces: namespace => spec.users})
}

# Namespaces & Namespace quotas

resource "kubernetes_namespace_v1" "namespace" {
  for_each = local.namespaces

  metadata {
    name = each.key
  }
}

resource "kubernetes_resource_quota_v1" "quota" {
  depends_on = [kubernetes_namespace_v1.namespace]
  for_each   = local.namespaces

  metadata {
    name      = "default-quota"
    namespace = each.key
  }

  spec {
    hard = {
      "requests.cpu"    = each.value.environment.resource-quota.cpu-request
      "requests.memory" = each.value.environment.resource-quota.memory-request
      "limits.memory"   = each.value.environment.resource-quota.memory-limit
      pods              = each.value.environment.resource-quota.pods
    }
  }
}

resource "kubernetes_limit_range_v1" "limit_range" {
  depends_on = [kubernetes_namespace_v1.namespace]
  for_each   = local.namespaces

  metadata {
    name      = "default-limits"
    namespace = each.key
  }

  spec {
    limit {
      type = "Container"
      default = {
        memory = each.value.environment.resource-defaults.memory-limit
      }
      default_request = {
        cpu    = each.value.environment.resource-defaults.cpu-request
        memory = each.value.environment.resource-defaults.memory-request
      }
    }
  }
}

# (Namespaced) Role(Binding)s

resource "kubernetes_role_v1" "namespace_role" {
  for_each = local.namespaces

  metadata {
    name      = "users"
    namespace = each.key
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "pods", "secrets", "services"] # "pods/log", "pods/portforward"
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "user_role_binding" {
  for_each   = local.namespace_users
  depends_on = [
    kubernetes_role_v1.namespace_role,
  ]

  metadata {
    name      = each.value.user
    namespace = each.value.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "users"
  }

  subject {
    kind      = "User"
    name      = "https://dex.${local.platform_domain}#${each.value.user}"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ClusterRole(Binding)s

resource "kubernetes_cluster_role_v1" "cluster_role" {
  for_each = local.users_namespaces

  metadata {
    name = "user-${each.key}"
  }
  
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "watch", "list"]
    resource_names = each.value # restrict to only allowed namespaces ?
  }
}

resource "kubernetes_cluster_role_binding_v1" "user_cluster_role_binding" {
  for_each   = toset(local.groups_users["developer"])
  depends_on = [
    kubernetes_cluster_role_v1.cluster_role
  ]

  metadata {
    name      = each.value
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "user-${each.key}"
  }

  subject {
    kind      = "User"
    name      = "https://dex.${local.platform_domain}#${each.value}"
    api_group = "rbac.authorization.k8s.io"
  }
}

# TODO: Network Policies
