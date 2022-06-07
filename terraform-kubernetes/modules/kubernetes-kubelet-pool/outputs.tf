output "client_security_group_id" {
  description = "A security group ID to add to instance-pool clients"
  value       = exoscale_security_group.clients.id
}

output "instance_pool_id" {
  description = "The instance-pool ID"
  value = exoscale_instance_pool.pool.id
}