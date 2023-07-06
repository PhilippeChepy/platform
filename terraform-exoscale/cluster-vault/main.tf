resource "exoscale_anti_affinity_group" "cluster" {
  name        = local.cluster_name
  description = "Hashicorp Vault (${local.cluster_name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${local.cluster_name}-cluster"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "TCP|8200|cluster" = { port = "8200", security_group = exoscale_security_group.cluster.id }
    "TCP|8201|cluster" = { port = "8201", security_group = exoscale_security_group.cluster.id }
    "TCP|8200|exoscale" = { port = "8200", public_security_group = "public-nlb-healthcheck-sources" }
    }, merge([
      for client in var.client_security_group : {
        "TCP|8200|sg:${client.name}" = { port = "8200", security_group = client.id }
      }
    ]...), merge([
      for cidr in toset(concat([for specs in var.specs.operators : specs.networks]...)) : {
        "TCP|22|cidr:${cidr}"   = { port = "22", cidr = cidr },
        "TCP|8200|cidr:${cidr}" = { port = "8200", cidr = cidr }
      }
    ]...)
  )

  security_group_id      = exoscale_security_group.cluster.id
  protocol               = "TCP"
  type                   = "INGRESS"
  start_port             = each.value["port"]
  end_port               = each.value["port"]
  cidr                   = try(each.value.cidr, null)
  user_security_group_id = try(each.value.security_group, null)
  public_security_group  = try(each.value.public_security_group, null)
}


resource "exoscale_nlb_service" "endpoint" {
  nlb_id      = var.internal_nlb.id
  zone        = var.specs.infrastructure.zone
  name        = "vault"
  description = "Hashicorp Vault API service"

  instance_pool_id = exoscale_instance_pool.cluster.id
  protocol         = "tcp"
  port             = 8200
  target_port      = 8200
  strategy         = "round-robin"

  healthcheck {
    mode     = "https"
    port     = 8200
    uri      = "/v1/sys/health"
    tls_sni  = local.cluster_name
    interval = 5
    timeout  = 2
    retries  = 2
  }
}

resource "exoscale_instance_pool" "cluster" {
  zone               = var.specs.infrastructure.zone
  name               = local.cluster_name
  size               = var.specs.vault.pool.size
  template_id        = var.specs.templates.vault
  instance_type      = var.specs.vault.pool.offering
  disk_size          = var.specs.vault.pool.disk_size_gb
  key_pair           = var.ssh_key
  instance_prefix    = local.cluster_name
  ipv6               = true
  affinity_group_ids = [exoscale_anti_affinity_group.cluster.id]
  security_group_ids = [exoscale_security_group.cluster.id]
  user_data = templatefile("${path.module}/templates/user-data", {
    domain             = var.specs.vault.endpoint
    cluster_name       = local.cluster_name
    cluster_ip_address = var.internal_nlb.ip_address
    backup_bucket      = "${var.specs.backup.prefix}-${var.specs.infrastructure.name}-vault.${var.specs.backup.zone}"
    backup_zone        = var.specs.backup.zone
  })

  # TODO: labels
}
