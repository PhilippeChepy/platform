variable "internal_nlb" {
  type = object({
    id         = string
    ip_address = string
  })
}

variable "specs" {
  type = object({
    infrastructure = object({
      name = string
      zone = string
      domain = string
    })
    templates = object({
      kubelet = string
    })
    operators = map(
      object({
        networks = list(string)
      })
    )
    kubernetes = object({
      domain = string
      network = object({
        inet4 = object({
          dns = string
        })
        inet6 = object({
          dns = string
        })
      })
    })
    kubelet_pool = map(
      object({
        size = number
        offering = string
        is_internal_ingress = optional(bool, false)
        disk = object({
          root_size_gb = number
          data_size_gb = optional(number, 0)
        })
        labels = optional(map(string), {})
        taints = optional(map(object({
          value  = string
          effect = string
        })), {})
      })
    )
  })
}

variable "ssh_key" {
  type = string
}

variable "bootstrap_token" {
  type = string
}