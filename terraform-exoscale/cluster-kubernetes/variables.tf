variable "internal_nlb" {
  type = object({
    id         = string
    ip_address = string
  })
}

variable "specs" {
  type = object({
    infrastructure = object({
      name   = string
      zone   = string
      domain = string
    })
    backup = object({
      prefix = string
      zone   = string
    })
    operators = map(
      object({
        networks = list(string)
      })
    )
    templates = object({
      kubernetes = string
    })
    kubernetes = object({
      domain = string,
      network = object({
        inet4 = object({
          pod_cidr   = string
          svc_cidr   = string
          kubernetes = string
        }),
        inet6 = object({
          pod_cidr   = string
          svc_cidr   = string
          kubernetes = string
        })
      })
      pool = object({
        size         = number
        offering     = string
        disk_size_gb = number
      })
    })
    ssh = object({
      algorithm = string
    })
  })
}

variable "ssh_key" {
  type = string
}

variable "etcd_servers" {
  type = string
}

variable "kubelet_security_groups" {
  type = set(object({
    id   = string
    name = string
  }))
}
