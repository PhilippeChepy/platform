locals {
  specs = yamldecode(file("${path.module}/../platform.specs.yaml"))

  enabled_condition = {
    cluster_vault            = ["cluster-vault", "cluster-etcd", "cluster-kubernetes", "cluster-kubernetes-pools"]
    cluster_etcd             = ["cluster-etcd", "cluster-kubernetes", "cluster-kubernetes-pools"]
    cluster_kubernetes       = ["cluster-kubernetes", "cluster-kubernetes-pools"]
    cluster_kubernetes_pools = ["cluster-kubernetes-pools"]
  }

  enabled = {
    cluster_vault            = try(contains(local.enabled_condition.cluster_vault, local.specs.infrastructure.phase), false)
    cluster_etcd             = try(contains(local.enabled_condition.cluster_etcd, local.specs.infrastructure.phase), false)
    cluster_kubernetes       = try(contains(local.enabled_condition.cluster_kubernetes, local.specs.infrastructure.phase), false)
    cluster_kubernetes_pools = try(contains(local.enabled_condition.cluster_kubernetes_pools, local.specs.infrastructure.phase), false)
  }

  enabled_module = {
    cluster_vault            = local.enabled.cluster_vault ? toset(["enabled"]) : []
    cluster_etcd             = local.enabled.cluster_etcd ? toset(["enabled"]) : []
    cluster_kubernetes       = local.enabled.cluster_kubernetes ? toset(["enabled"]) : []
    cluster_kubernetes_pools = local.enabled.cluster_kubernetes_pools ? toset(["enabled"]) : []
  }
}
