output "client_security_group_id" {
  description = "A security group id to add to cluster clients."
  value       = exoscale_security_group.clients.id
}

output "url" {
  description = "Cluster url, for use by clients."
  value       = "https://${exoscale_elastic_ip.endpoint.ip_address}:2379"
}

output "cluster_ip_address" {
  description = "Cluster IP address."
  value       = exoscale_elastic_ip.endpoint.ip_address
}
