output "client_security_group_id" {
  description = "A security group id to add to cluster clients."
  value       = exoscale_security_group.clients.id
}
