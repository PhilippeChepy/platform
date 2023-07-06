output "cluster_security_group" {
  value = {
    id = exoscale_security_group.cluster.id
    name = "${local.cluster_name}-cluster"
  }
}
