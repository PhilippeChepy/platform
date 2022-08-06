output "url" {
  description = "The URL of the cluster, for use by clients."
  value       = "https://${data.exoscale_nlb.endpoint.ip_address}:8200"
}

output "client_security_group_id" {
  description = "A security group id to add to cluster clients."
  value       = exoscale_security_group.clients.id
}

output "server_security_group_id" {
  description = "The cluster peer's security group id (if using Kubernetes authentication, allow this SG to connect to API server)."
  value       = exoscale_security_group.cluster.id
}

output "instances" {
  description = "Cluster's instances"
  value       = exoscale_instance_pool.cluster.instances
}