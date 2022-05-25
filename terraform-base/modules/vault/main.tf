# Base resources from Exoscale

resource "exoscale_anti_affinity_group" "cluster" {
  name        = var.name
  description = "Hashicorp Vault (${var.name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${var.name}-server"
}

resource "exoscale_security_group" "clients" {
  name = "${var.name}-clients"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "tcp-8200--${exoscale_security_group.cluster.name}" = { port = "8200", security_group = exoscale_security_group.cluster.id }
    "tcp-8201--${exoscale_security_group.cluster.name}" = { port = "8201", security_group = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.admin_security_groups :
    "tcp-22--${name}" => { port = "22", security_group = id }
    }, {
    for name, id in merge({ clients = exoscale_security_group.clients.id }, var.client_security_groups) :
    "tcp-8200--${name}" => { port = "8200", security_group = id }
  })

  security_group_id      = exoscale_security_group.cluster.id
  protocol               = "TCP"
  type                   = "INGRESS"
  start_port             = each.value["port"]
  end_port               = each.value["port"]
  cidr                   = try(each.value.cidr, null)
  user_security_group_id = try(each.value.security_group, null)
}

resource "exoscale_elastic_ip" "endpoint" {
  zone        = var.zone
  description = "Hashicorp Vault API endpoint ${var.name}"

  healthcheck {
    mode            = "https"
    port            = "8200"
    uri             = "/v1/sys/health"
    tls_sni         = var.name
    tls_skip_verify = true

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
  security_group_ids = [exoscale_security_group.cluster.id]
  elastic_ip_ids     = [exoscale_elastic_ip.endpoint.id]
  user_data = templatefile("${path.module}/templates/user-data", {
    domain             = var.domain
    cluster_name       = var.name
    cluster_ip_address = exoscale_elastic_ip.endpoint.ip_address
  })

  labels = var.labels
}
