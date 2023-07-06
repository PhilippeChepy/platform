output "inventory" {
  value = <<-EOT
all:
  vars:
    ansible_ssh_user: ubuntu
    ansible_ssh_extra_args: "-o StrictHostKeyChecking=no"
    ansible_ssh_private_key_file: artifacts/id_${lower(var.specs.ssh.algorithm)}
  children:
    etcd:
      hosts:
%{~for instance in exoscale_instance_pool.cluster.instances}
        ${instance.name}:
          ansible_host: ${instance.public_ip_address~}
%{endfor}
EOT
}

output "instances" {
  value = {
    for instance in exoscale_instance_pool.cluster.instances : instance.name => instance
  }
}

output "cluster_security_group" {
  value = {
    id = exoscale_security_group.cluster.id
    name = "${local.cluster_name}-cluster"
  }
}
