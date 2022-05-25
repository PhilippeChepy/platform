// PKI

module "ca_certificate" {
  source = "git@github.com:PhilippeChepy/terraform-tls-root-ca.git"

  key_algorithm = local.platform_default_tls_algorithm.algorithm
  ecdsa_curve   = try(local.platform_default_tls_algorithm.ecdsa_curve, null)
  rsa_bits      = try(local.platform_default_tls_algorithm.rsa_bits, null)

  subject = merge(
    { common_name = "Platform Root CA 1" },
    local.platform_default_tls_subject
  )
  validity_period_hours = var.root_ca_validity_period_hours
}

// SSH automation

resource "tls_private_key" "management_key" {
  algorithm   = local.platform_ssh_algorithm.algorithm
  ecdsa_curve = try(local.platform_ssh_algorithm.ecdsa_curve, null)
  rsa_bits    = try(local.platform_ssh_algorithm.rsa_bits, null)
}

resource "exoscale_ssh_key" "management_key" {
  name       = "${local.platform_name}-management"
  public_key = tls_private_key.management_key.public_key_openssh
}

# Admin access

data "http" "operator_ip_address" {
  url = "http://ipconfig.me"
}

resource "exoscale_security_group" "operator" {
  name = "${local.platform_name}-operator"

  external_sources = ["${chomp(data.http.operator_ip_address.body)}/32"]
}

# Vault

module "vault_cluster" {
  source = "./modules/vault"
  zone   = local.platform_zone
  name   = "${local.platform_name}-vault"

  template_id            = local.platform_components.vault.template
  admin_security_groups  = { terraform = exoscale_security_group.operator.id }
  client_security_groups = { terraform = exoscale_security_group.operator.id }
  ssh_key                = "${local.platform_name}-management"

  labels = {
    name = local.platform_name
    zone = local.platform_zone
    role = "vault"
  }

  domain       = local.platform_domain
  cluster_size = var.vault_cluster_size
}

# Local artifacts

resource "local_file" "root_ca_certificate_pem" {
  content  = module.ca_certificate.certificate_pem
  filename = "${path.module}/../artifacts/ca-certificate.pem"
}

resource "local_sensitive_file" "root_ca_private_key_pem" {
  content         = module.ca_certificate.private_key_pem
  filename        = "${path.module}/../artifacts/ca-certificate.key"
  file_permission = 0600
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.management_key.private_key_openssh
  filename        = "${path.module}/../artifacts/id_${lower(local.platform_ssh_algorithm.algorithm)}"
  file_permission = 0600
}

resource "local_file" "properties_base" {
  content = jsonencode({
    operator_security_group = exoscale_security_group.operator.id
  })
  filename = "${path.module}/../artifacts/properties-base.json"
}

resource "local_file" "properties_vault" {
  content = jsonencode({
    client_security_group = module.vault_cluster.client_security_group_id
    server_security_group = module.vault_cluster.server_security_group_id
    url                   = module.vault_cluster.url
    ip_address            = module.vault_cluster.ip_address
  })
  filename = "${path.module}/../artifacts/properties-vault.json"
}

resource "local_file" "cluster_inventory" {
  content  = <<-EOT
all:
  vars:
    ansible_ssh_user: ubuntu
    ansible_ssh_extra_args: "-o StrictHostKeyChecking=no"
    ansible_ssh_private_key_file: artifacts/id_${lower(local.platform_ssh_algorithm.algorithm)}
    
    vault_cluster_name: "${local.platform_name}-vault"
    vault_ip_address: ${module.vault_cluster.ip_address}
  children:
    vault:
      hosts:
%{~for instance in module.vault_cluster.instances}
        ${instance.name}:
          ansible_host: ${instance.public_ip_address~}
%{endfor}
EOT
  filename = "${path.module}/../artifacts/inventory_vault.yml"
}