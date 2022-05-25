variable "root_ca_validity_period_hours" {
  type    = number
  default = 262980 # 30y
}

variable "vault_cluster_size" {
  type    = number
  default = 3
}