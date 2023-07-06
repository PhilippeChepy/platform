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
      etcd = string
    })
    etcd = object({
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

variable "client_security_group" {
  type = set(object({
    id   = string
    name = string
  }))
}
