locals {
  node_base_purpose = {
    "general" = {
      size          = 3
      instance_type = "standard.small"
      root_size     = 10
    }
  }

  node_storage = {
    "ceph-mon" = {
      size          = 3
      instance_type = "standard.small"
      root_size     = 10
      data_size     = 60
      labels        = { "${local.platform_domain}/role" = "monitor", "${local.platform_domain}/autoscaling" = "requires-deactivation" }
      taints        = { "${local.platform_domain}/role" = { value = "monitor", effect = "NoSchedule" } }
    },
    "ceph-osd" = {
      size          = 3
      instance_type = "standard.small"
      root_size     = 10
      data_size     = 400
      labels        = { "${local.platform_domain}/role" = "object-storage-daemon", "${local.platform_domain}/autoscaling" = "requires-deactivation" }
      taints        = { "${local.platform_domain}/role" = { value = "object-storage-daemon", effect = "NoSchedule" } }
    },
    "ceph-mds" = {
      size          = 2
      instance_type = "standard.small"
      root_size     = 10
      data_size     = 5
      labels        = { "${local.platform_domain}/role" = "metadata-server", "${local.platform_domain}/autoscaling" = "requires-deactivation" }
      taints        = { "${local.platform_domain}/role" = { value = "metadata", effect = "NoSchedule" } }
    }
  }

  node_ingress = {
    for name, ingress in local.platform_components.kubernetes.ingresses :
    "ingress-${name}" => {
      size          = ingress.pool_size
      instance_type = "standard.tiny"
      root_size     = 10
      labels        = { "${local.platform_domain}/ingress" = name, "${local.platform_domain}/autoscaling" = "requires-deactivation" }
      taints        = { "${local.platform_domain}/ingress" = { value = name, effect = "NoSchedule" } }
    }
  }
}
