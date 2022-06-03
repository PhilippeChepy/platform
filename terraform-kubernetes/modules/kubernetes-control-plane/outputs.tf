output "cluster_security_group_id" {
  description = "A security group ID attached to control plane nodes."
  value       = exoscale_security_group.cluster.id
}

output "client_security_group_id" {
  description = "A security group id to add to cluster clients."
  value       = exoscale_security_group.clients.id
}

output "kubelet_security_group_id" {
  value = exoscale_security_group.kubelet.id
}

output "cluster_ip_address" {
  value = exoscale_elastic_ip.endpoint.ip_address
}