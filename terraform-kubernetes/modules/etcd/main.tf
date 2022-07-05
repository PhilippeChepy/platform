# Base resources from Exoscale

resource "exoscale_anti_affinity_group" "cluster" {
  name        = var.name
  description = "Etcd (${var.name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${var.name}-server"
}

resource "exoscale_security_group" "clients" {
  name = "${var.name}-clients"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "tcp-2379-2380--${exoscale_security_group.cluster.name}" = { type = "INGRESS", protocol = "TCP", port = "2379-2380", source = exoscale_security_group.cluster.id, target = exoscale_security_group.cluster.id }
    "tcp-2378-2379--${exoscale_security_group.clients.name}" = { type = "INGRESS", protocol = "TCP", port = "2378-2379", source = exoscale_security_group.clients.id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.admin_security_groups :
    "tcp-22-22--${name}" => { type = "INGRESS", protocol = "TCP", port = "22", source = id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in merge(var.client_security_groups) :
    "tcp-2379-2379--${name}" => { type = "INGRESS", protocol = "TCP", port = "2379", source = id, target = exoscale_security_group.cluster.id }
  })

  security_group_id      = try(each.value.target, null)
  protocol               = "TCP"
  type                   = "INGRESS"
  start_port             = try(split("-", each.value["port"])[0], each.value["port"])
  end_port               = try(split("-", each.value["port"])[1], each.value["port"])
  user_security_group_id = try(each.value.source, null)
}

resource "exoscale_elastic_ip" "endpoint" {
  zone        = var.zone
  description = "etcd endpoint ${var.name}"

  healthcheck {
    mode         = "http"
    port         = 2378
    uri          = "/healthz"
    interval     = 5
    timeout      = 2
    strikes_ok   = 2
    strikes_fail = 2
  }
}

resource "exoscale_instance_pool" "cluster" {
  zone               = var.zone
  name               = var.name
  size               = var.cluster_size
  template_id        = var.template_id
  instance_type      = var.instance_type
  disk_size          = var.disk_size
  key_pair           = var.ssh_key
  instance_prefix    = var.name
  ipv6               = var.ipv6
  affinity_group_ids = [exoscale_anti_affinity_group.cluster.id]
  security_group_ids = concat([exoscale_security_group.cluster.id], values(var.additional_security_groups))
  elastic_ip_ids     = [exoscale_elastic_ip.endpoint.id]
  user_data = templatefile("${path.module}/templates/user-data", {
    domain                          = var.domain
    etcd_cluster_ip_address         = exoscale_elastic_ip.endpoint.ip_address
    etcd_cluster_instance_pool_name = var.name
    etcd_cluster_name               = var.name
    etcd_cluster_zone               = var.zone
    vault_ca_pem                    = base64encode(var.vault.ca_certificate_pem)
    vault_cluster_address           = var.vault.url
    vault_cluster_name              = var.vault.cluster_name
    vault_cluster_healthcheck_url   = var.vault.healthcheck_url
    backup_bucket                   = var.backup.bucket
    backup_zone                     = var.backup.zone
  })

  labels = var.labels
}
