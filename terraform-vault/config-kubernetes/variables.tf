variable "internal_nlb" {
  type = object({
    ip_address = string
  })
}

variable "specs" {
  type = object({
    infrastructure = object({
      name = string
    })
    backup = object({
      prefix = string
      zone   = string
      encryption = object({
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
      })
    })
    vault = object({
      endpoint = string
    })
    kubernetes = object({
      domain   = string
    })
    pki = object({
      service_account = object({
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
      })
      kubernetes_apiserver = object({
        ttl_hours   = number
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
        common_name = string
        subject = object({
          organizational_unit = optional(string)
          organization        = optional(string)
          street_address      = optional(list(string))
          postal_code         = optional(string)
          locality            = optional(string)
          province            = optional(string)
          country             = optional(string)
        })
      })
      kubernetes_kubelet = object({
        ttl_hours   = number
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
        common_name = string
        subject = object({
          organizational_unit = optional(string)
          organization        = optional(string)
          street_address      = optional(list(string))
          postal_code         = optional(string)
          locality            = optional(string)
          province            = optional(string)
          country             = optional(string)
        })
      })
      kubernetes_aggregation_layer = object({
        ttl_hours   = number
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
        common_name = string
        subject = object({
          organizational_unit = optional(string)
          organization        = optional(string)
          street_address      = optional(list(string))
          postal_code         = optional(string)
          locality            = optional(string)
          province            = optional(string)
          country             = optional(string)
        })
      })
      kubernetes_client = object({
        ttl_hours   = number
        algorithm   = string
        ecdsa_curve = optional(string)
        rsa_bits    = optional(number)
        common_name = string
        subject = object({
          organizational_unit = optional(string)
          organization        = optional(string)
          street_address      = optional(list(string))
          postal_code         = optional(string)
          locality            = optional(string)
          province            = optional(string)
          country             = optional(string)
        })
      })
    })
  })
}
