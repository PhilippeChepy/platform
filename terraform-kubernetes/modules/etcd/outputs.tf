output "client_security_group_id" {
  description = "A security group id to add to cluster clients."
  value       = exoscale_security_group.clients.id
}

output "url" {
  description = "Cluster url, for use by clients."
  value       = "https://${data.exoscale_nlb.endpoint.ip_address}:2379"
}

output "healthcheck_url" {
  description = "Cluster healthcheck url, for use along the NLB."
  value       = "http://${data.exoscale_nlb.endpoint.ip_address}:2378/healthz"
}

output "instances" {
  description = "Cluster's instances"
  value       = exoscale_instance_pool.cluster.instances
}