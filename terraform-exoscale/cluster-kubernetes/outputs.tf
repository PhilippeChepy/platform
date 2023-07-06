output "cluster_security_group" {
  value = {
    id = exoscale_security_group.cluster.id
    name = "${local.cluster_name}-cluster"
  }
}

output "bootstrap_token" {
  value = {
    id = random_string.token_id.result
    secret = random_string.token_secret.result
  }
}

output "api_server_address" {
  value = [
    for instance in exoscale_instance_pool.cluster.instances : instance.public_ip_address
  ]
}