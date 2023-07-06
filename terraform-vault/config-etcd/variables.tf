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
    pki = object({
      etcd = object({
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
