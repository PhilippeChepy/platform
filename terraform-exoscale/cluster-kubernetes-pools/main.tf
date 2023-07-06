resource "exoscale_anti_affinity_group" "cluster" {
  name        = local.cluster_name
  description = "Kubernetes nodes (${local.cluster_name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${local.cluster_name}-cluster"
}

resource "exoscale_security_group" "clients" {
  name = "${local.cluster_name}-clients"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "ICMP|8:0|cluster" = { protocol = "ICMP", icmp_type = "8", icmp_code = "0", security_group = exoscale_security_group.cluster.id }
    "TCP|4240|cluster" = { port = "4240", security_group = exoscale_security_group.cluster.id }
    "UDP|8472|cluster" = { protocol = "UDP", port = "8472", security_group = exoscale_security_group.cluster.id }
    "TCP|10250|cluster" = { protocol = "TCP", port = "10250", security_group = exoscale_security_group.cluster.id }

    "TCP|31080|world-inet4" = { port = "31080", cidr = "0.0.0.0/0" }
    "TCP|31443|world-inet4" = { port = "31443", cidr = "0.0.0.0/0" }
    "TCP|31080|world-inet6" = { port = "31080", cidr = "::/0" }
    "TCP|31443|world-inet6" = { port = "31443", cidr = "::/0" }
    },
    merge([
      for cidr in concat([for specs in var.specs.operators : specs.networks]...) : {
        "TCP|22|cidr:${cidr}"   = { port = "22", cidr = cidr },
      }
    ]...)
  )

  security_group_id      = exoscale_security_group.cluster.id
  protocol               = try(each.value.protocol, "TCP")
  type                   = "INGRESS"
  start_port             = try(each.value.port, null)
  end_port               = try(each.value.port, null)
  icmp_type              = try(each.value.icmp_type, null)
  icmp_code              = try(each.value.icmp_code, null)
  cidr                   = try(each.value.cidr, null)
  user_security_group_id = try(each.value.security_group, null)
  public_security_group = try(each.value.public_security_group, null)
}

resource "exoscale_instance_pool" "cluster" {
  for_each = var.specs.kubelet_pool

  zone               = var.specs.infrastructure.zone
  name               = "${local.cluster_name}-${each.key}"
  size               = each.value.size
  template_id        = var.specs.templates.kubelet
  instance_type      = each.value.offering
  disk_size          = each.value.disk.root_size_gb + try(each.value.disk.data_size_gb, 0)
  key_pair           = var.ssh_key
  instance_prefix    = "${local.cluster_name}-${each.key}"
  ipv6               = true
  affinity_group_ids = [exoscale_anti_affinity_group.cluster.id]
  security_group_ids = [exoscale_security_group.cluster.id]

  user_data = templatefile("${path.module}/templates/user-data", {
    apiserver_url             = "https://${var.internal_nlb.ip_address}:6443"
    authentication_token      = var.bootstrap_token
    controlplane_ca_pem       = base64encode(try(file("${path.module}/../../artifacts/kubernetes-control-plane-ca.pem"), "")) # HACK: fallback to empty string because of Terraform trying to interpolate while the module is not (yet) enabled
    kube_apiserver_ip_address = var.internal_nlb.ip_address
    kube_cluster_domain       = var.specs.kubernetes.domain
    kube_dns_service_ipv4     = var.specs.kubernetes.network.inet4.dns
    kube_dns_service_ipv6     = var.specs.kubernetes.network.inet6.dns
    node_ca_pem               = base64encode(try(file("${path.module}/../../artifacts/kubelet-ca.pem"), "")) # HACK: fallback to empty string because of Terraform trying to interpolate while the module is not (yet) enabled
    labels                    = join(",", [for key, value in each.value.labels : "${key}=${value}"])
    taints                    = each.value.taints
    root_size                 = each.value.disk.root_size_gb
    storage_partition         = try(each.value.disk.data_size_gb, 0) > 0
  })

  # TODO: labels
}


resource "exoscale_nlb_service" "endpoint_http" {
  for_each = toset([for name, pool in var.specs.kubelet_pool: name if pool.is_internal_ingress])

  nlb_id      = var.internal_nlb.id
  zone        = var.specs.infrastructure.zone
  name        = "ingress-http"
  description = "Ingress HTTP"

  instance_pool_id = exoscale_instance_pool.cluster[each.key].id
  protocol         = "tcp"
  port             = 80
  target_port      = 31080
  strategy         = "round-robin"

  healthcheck {
    mode     = "tcp"
    port     = 31080
    interval = 5
    timeout  = 2
    retries  = 2
  }
}

resource "exoscale_nlb_service" "endpoint_https" {
  for_each = toset([for name, pool in var.specs.kubelet_pool: name if pool.is_internal_ingress])

  nlb_id      = var.internal_nlb.id
  zone        = var.specs.infrastructure.zone
  name        = "ingress-https"
  description = "Ingress HTTPS"

  instance_pool_id = exoscale_instance_pool.cluster[each.key].id
  protocol         = "tcp"
  port             = 443
  target_port      = 31443
  strategy         = "round-robin"

  healthcheck {
    mode     = "tcp"
    port     = 31443
    interval = 5
    timeout  = 2
    retries  = 2
  }
}
