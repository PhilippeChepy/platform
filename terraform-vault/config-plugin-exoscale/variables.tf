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
    })
  })
}

variable "exoscale_auth_plugin_hash" {
  type    = string
  default = "380c1f0b44c676c10a7895b9c3b559dee6797d5583d606b77f131ce140036e37"
}
