# Base resources from Exoscale

resource "exoscale_anti_affinity_group" "pool" {
  name        = var.name
  description = "Kubernetes Kubelet Pool (${var.name})"
}

resource "exoscale_security_group" "pool" {
  name = var.name
}

resource "exoscale_security_group" "clients" {
  name = "${var.name}-clients"
}

resource "exoscale_security_group_rule" "pool_rule" {
  for_each = merge({
    for name, id in var.admin_security_groups :
    "tcp-22-22--${name}" => { type = "INGRESS", protocol = "TCP", port = "22", source = id, target = exoscale_security_group.pool.id }
  })

  security_group_id      = try(each.value.target, null)
  protocol               = "TCP"
  type                   = "INGRESS"
  start_port             = try(split("-", each.value["port"])[0], each.value["port"])
  end_port               = try(split("-", each.value["port"])[1], each.value["port"])
  user_security_group_id = try(each.value.source, null)
}

resource "exoscale_instance_pool" "pool" {
  zone               = var.zone
  name               = var.name
  size               = var.pool_size
  template_id        = var.template_id
  instance_type      = var.instance_type
  disk_size          = var.disk_size
  key_pair           = var.ssh_key
  instance_prefix    = var.name
  ipv6               = var.ipv6
  affinity_group_ids = [exoscale_anti_affinity_group.pool.id]
  security_group_ids = concat([exoscale_security_group.pool.id, exoscale_security_group.clients.id], values(var.additional_security_groups))
  user_data = templatefile("${path.module}/templates/user-data", {
    apiserver_url                    = "https://${var.kubernetes.apiserver_cluster_ip_address}:6443"
    authentication_token             = var.kubernetes.kubelet_authentication_token
    controlplane_ca_pem_b64          = base64encode(var.kubernetes.controlplane_ca_pem)
    domain                           = var.domain
    kube_cluster_domain              = var.kubernetes.cluster_domain
    kube_cluster_healthcheck_address = "http://${var.kubernetes.apiserver_cluster_ip_address}:6444/healthz"
    kube_dns_service_ipv4            = var.kubernetes.dns_service_ipv4
    kube_dns_service_ipv6            = var.kubernetes.dns_service_ipv6
    node_ca_pem_b64                  = base64encode(var.kubernetes.kubelet_ca_pem)
    labels                           = local.kubelet_labels
    taints                           = var.kubelet_taints
  })

  labels = var.labels
}
