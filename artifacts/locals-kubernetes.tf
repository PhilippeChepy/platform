data "local_file" "kubernetes_inventory" {
  filename = "${path.module}/../artifacts/kubernetes-inventory.yml"
}

locals {
  kubernetes_inventory_vars = yamldecode(data.local_file.kubernetes_inventory.content).all.vars

  kubernetes = {
    apiserver_url                     = local.kubernetes_inventory_vars.kubernetes_apiserver_url
    control_plane_ip_address          = local.kubernetes_inventory_vars.kubernetes_control_plane_ip_address
    control_plane_instance_ip_address = local.kubernetes_inventory_vars.kubernetes_control_plane_instance_ip_address
  }
}