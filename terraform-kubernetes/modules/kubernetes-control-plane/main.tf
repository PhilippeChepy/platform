# Base resources from Exoscale

resource "exoscale_anti_affinity_group" "cluster" {
  name        = var.name
  description = "Kubernetes control-plane (${var.name})"
}

resource "exoscale_security_group" "cluster" {
  name = "${var.name}-controllers"
}

resource "exoscale_security_group" "clients" {
  name = "${var.name}-clients"
}

resource "exoscale_security_group" "kubelet" {
  name = "${var.name}-nodes"
}

resource "exoscale_security_group_rule" "cluster_rule" {
  for_each = merge({
    "tcp-6443-6443--${exoscale_security_group.clients.name}" = { type = "INGRESS", protocol = "TCP", port = "6443", source = exoscale_security_group.clients.id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.admin_security_groups :
    "tcp-22-22--${name}" => { type = "INGRESS", protocol = "TCP", port = "22", source = id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.admin_security_groups :
    "tcp-6444-6444--${name}" => { type = "INGRESS", protocol = "TCP", port = "6444", source = id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.client_security_groups :
    "tcp-6443-6443--${name}" => { type = "INGRESS", protocol = "TCP", port = "6443", source = id, target = exoscale_security_group.cluster.id }
    }, {
    for name, id in var.client_security_groups :
    "tcp-6444-6444--${name}" => { type = "INGRESS", protocol = "TCP", port = "6444", source = id, target = exoscale_security_group.cluster.id }
    }, {
    # node <-> node
    "icmp-8-0--kube-cilium-healthcheck"        = { type = "INGRESS", protocol = "ICMP", icmp_type = "8", icmp_code = "0", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    "tcp-4240-4240--kube-cilium-healthcheck"   = { type = "INGRESS", protocol = "TCP", port = "4240", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    "tcp-4244-4244--kube-cilium-hubble-server" = { type = "INGRESS", protocol = "TCP", port = "4244", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    "tcp-4245-4245--kube-cilium-hubble-relay"  = { type = "INGRESS", protocol = "TCP", port = "4245", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    "tcp-8472-8472--kube-cilium-vxlan"         = { type = "INGRESS", protocol = "UDP", port = "8472", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    "tcp-10250-10250--svc-kubelet-logs"        = { type = "INGRESS", protocol = "TCP", port = "10250", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.kubelet.id }
    # node -> control-plane
    "tcp-6443-6443--kubelet"      = { type = "INGRESS", protocol = "TCP", port = "6443", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.cluster.id }
    "tcp-6444-6444--kubelet"      = { type = "INGRESS", protocol = "TCP", port = "6444", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.cluster.id }
    "tcp-8091-8091--konnectivity" = { type = "INGRESS", protocol = "TCP", port = "8091", source = exoscale_security_group.kubelet.id, target = exoscale_security_group.cluster.id }
    # control-plane -> node
    "tcp-10250-10250--apiserver-kubelet-logs" = { type = "INGRESS", protocol = "TCP", port = "10250", source = exoscale_security_group.cluster.id, target = exoscale_security_group.kubelet.id }
  })

  security_group_id      = try(each.value.target, null)
  protocol               = each.value.protocol
  type                   = each.value.type
  icmp_type              = try(each.value.icmp_type, null)
  icmp_code              = try(each.value.icmp_code, null)
  start_port             = try(split("-", each.value["port"])[0], each.value["port"], null)
  end_port               = try(split("-", each.value["port"])[1], each.value["port"], null)
  user_security_group_id = try(each.value.source, null)
}

resource "exoscale_elastic_ip" "endpoint" {
  zone        = var.zone
  description = "API server endpoint ${var.name}"

  healthcheck {
    mode         = "http"
    port         = 6444
    uri          = "/healthz"
    interval     = 5
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
    domain                         = var.domain
    etcd_address                   = var.etcd.address
    etcd_healthcheck_url           = var.etcd.healthcheck_url
    kubernetes_cluster_domain      = var.kubernetes.cluster_domain
    kubernetes_cluster_ip_address  = exoscale_elastic_ip.endpoint.ip_address
    kubernetes_cluster_internal_ip = var.kubernetes.apiserver_service_ipv4
    kubernetes_cluster_name        = var.name
    kubernetes_service_cidr_ipv4   = var.kubernetes.service_cidr_ipv4
    kubernetes_service_cidr_ipv6   = var.kubernetes.service_cidr_ipv6
    vault_ca_pem                   = base64encode(var.vault.ca_certificate_pem)
    vault_cluster_address          = var.vault.url
    vault_cluster_healthcheck_url  = var.vault.healthcheck_url
    vault_cluster_name             = var.vault.cluster_name
    zone                           = var.zone

    # We need kubelet bootstrap RBAC settings very early, because kubelets
    # won't retry failed apiserver authentication indefinitly.
    # So, we do the provisioning of RBAC settings, and bootstrap token (id, secret),
    # and we apply this configuration right after the apiserver is available.
    kubelet_bootstrap_manifests = base64encode(templatefile("${path.module}/templates/manifests/kubelet-bootstrap-token.yaml", {
      token_id     = var.kubernetes.bootstrap_token_id
      token_secret = var.kubernetes.bootstrap_token_secret
    }))

    exoscale_cloud_controller_manager_manifests = base64encode(file("${path.module}/templates/manifests/exoscale-cloud-controller-manager.yaml"))
  })

  labels = var.labels
}

resource "null_resource" "wait" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "while ! nc -z -w5 ${exoscale_elastic_ip.endpoint.ip_address} 6443; do echo \"Waiting for control-plane availability\"; done"
  }
}