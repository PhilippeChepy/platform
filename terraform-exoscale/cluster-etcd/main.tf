resource "exoscale_anti_affinity_group" "cluster" {
  name        = local.cluster_name
  description = "Etcd (${local.cluster_name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${local.cluster_name}-cluster"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "TCP|2378|cluster" = { port = "2378", security_group = exoscale_security_group.cluster.id }
    "TCP|2379|cluster" = { port = "2379", security_group = exoscale_security_group.cluster.id }
    "TCP|2380|cluster" = { port = "2380", security_group = exoscale_security_group.cluster.id }
    "TCP|2378|exoscale" = { port = "2378", public_security_group = "public-nlb-healthcheck-sources" }
    }, merge([
      for client in var.client_security_group : {
        "TCP|2379|sg:${client.name}" = { port = "2379", security_group = client.id }
      }
    ]...), merge([
      for cidr in concat([for specs in var.specs.operators : specs.networks]...) : {
        "TCP|22|cidr:${cidr}"   = { port = "22", cidr = cidr },
        "TCP|2379|cidr:${cidr}" = { port = "2379", cidr = cidr }
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
  name        = "etcd"
  description = "Etcd API service"

  instance_pool_id = exoscale_instance_pool.cluster.id
  protocol         = "tcp"
  port             = 2379
  target_port      = 2379
  strategy         = "round-robin"

  healthcheck {
    mode     = "http"
    port     = 2378
    uri      = "/healthz"
    interval = 5
    timeout  = 2
    retries  = 2
  }
}

resource "exoscale_instance_pool" "cluster" {
  zone               = var.specs.infrastructure.zone
  name               = local.cluster_name
  size               = var.specs.etcd.pool.size
  template_id        = var.specs.templates.etcd
  instance_type      = var.specs.etcd.pool.offering
  disk_size          = var.specs.etcd.pool.disk_size_gb
  key_pair           = var.ssh_key
  instance_prefix    = local.cluster_name
  ipv6               = true
  affinity_group_ids = [exoscale_anti_affinity_group.cluster.id]
  security_group_ids = [exoscale_security_group.cluster.id]
  user_data = templatefile("${path.module}/templates/user-data", {
    domain                          = var.specs.infrastructure.domain
    etcd_cluster_ip_address         = var.internal_nlb.ip_address
    etcd_cluster_instance_pool_name = local.cluster_name
    etcd_cluster_name               = local.cluster_name
    etcd_cluster_zone               = var.specs.infrastructure.zone
    vault_ca_pem                    = base64encode(try(file("${path.module}/../../artifacts/ca-certificate.pem"), "")) # HACK: fallback to empty string because of Terraform trying to interpolate while the module is not (yet) enabled
    vault_cluster_address           = "https://${var.internal_nlb.ip_address}:8200"
    vault_cluster_name              = "${var.specs.infrastructure.name}-vault"
    vault_cluster_healthcheck_url   = "https://${var.internal_nlb.ip_address}:8200/v1/sys/health"
    backup_bucket                   = "${var.specs.backup.prefix}-${var.specs.infrastructure.name}-etcd.${var.specs.backup.zone}"
    backup_zone                     = var.specs.backup.zone
  })

  # TODO: labels
}
