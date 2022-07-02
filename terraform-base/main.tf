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
  count = try(local.platform_admin_networks == "auto", false) ? 1 : 0
  url   = "http://ipconfig.me"
}

resource "exoscale_security_group" "operator" {
  name = "${local.platform_name}-operator"

  external_sources = try(local.platform_admin_networks == "auto", false) ? ["${chomp(data.http.operator_ip_address[0].body)}/32"] : tolist(local.platform_admin_networks)
}

# Backup buckets

resource "random_string" "random_id" {
  length  = 6
  lower   = true
  numeric = true
  special = false
  upper   = false
}

resource "aws_s3_bucket" "backup" {
  for_each = toset(["vault", "etcd"])
  provider = aws.sos
  bucket   = "${local.platform_name}-${random_string.random_id.result}-${each.value}-backups.${local.platform_backup_zone}"

  # Disable unsupported features
  lifecycle {
    ignore_changes = [
      object_lock_configuration,
    ]
  }
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

resource "local_file" "cluster_inventory" {
  content  = <<-EOT
all:
  vars:
    ansible_ssh_user: ubuntu
    ansible_ssh_extra_args: "-o StrictHostKeyChecking=no"
    ansible_ssh_private_key_file: artifacts/id_${lower(local.platform_ssh_algorithm.algorithm)}
    
    base_operator_security_group: "${exoscale_security_group.operator.id}"
    rclone_backup_vault_bucket: "${aws_s3_bucket.backup["vault"].bucket}"
    rclone_backup_vault_zone: "${local.platform_backup_zone}"
    rclone_backup_etcd_bucket: "${aws_s3_bucket.backup["etcd"].bucket}"
    rclone_backup_etcd_zone: "${local.platform_backup_zone}"
    vault_cluster_name: "${local.platform_name}-vault"
    vault_ip_address: "${module.vault_cluster.ip_address}"
    vault_url: "${module.vault_cluster.url}"
    vault_client_security_group_id: "${module.vault_cluster.client_security_group_id}"
    vault_server_security_group_id: "${module.vault_cluster.server_security_group_id}"
  children:
    vault:
      hosts:
%{~for instance in module.vault_cluster.instances}
        ${instance.name}:
          ansible_host: ${instance.public_ip_address~}
%{endfor}
EOT
  filename = "${path.module}/../artifacts/inventory.yml"
}
