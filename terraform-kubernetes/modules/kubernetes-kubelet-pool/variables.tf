# Underlying infrastructure settings

variable "zone" {
  description = "Target zone of the infrastructure (e.g. 'ch-gva-2', 'ch-dk-2', 'de-fra-1', 'de-muc-1', etc.)."
  type        = string
}

variable "name" {
  description = "The base name of cluster components."
  type        = string
}

variable "template_id" {
  description = "OS template id to use. Reference implementation is built using the `packer-exoscale` repository."
  type        = string
}

variable "instance_type" {
  description = "Service offering of member instances."
  type        = string
  default     = "standard.small"
}

variable "disk_size" {
  description = "Size of the root partition in GB. `10` should be sufficient."
  type        = number
  default     = 10
}

variable "ipv4" {
  description = "If IPv4 must be enabled on member instances (can only be 'true' for now)."
  type        = bool
  default     = true
}

variable "ipv6" {
  description = "If IPv6 must be enabled on member instances."
  type        = bool
  default     = true
}

variable "additional_security_groups" {
  description = "A map (key => ID) of security groups to apply to cluster members."
  type        = map(string)
  default     = {}
}

variable "admin_security_groups" {
  description = "A map (key => ID) of security groups authorized to access SSH"
  type        = map(string)
  default     = {}
}

variable "security_group_rules" {
  description = "A map (key => specs) of security group rules to add to kubelet security group"
  type = map(object({
    protocol          = string
    type              = string
    port              = string
    cidr              = optional(string)
    security_group_id = optional(string)
  }))
  default = {}
}

variable "ssh_key" {
  description = "Authorized SSH key."
  type        = string
}

variable "labels" {
  description = "Additional labels for cluster's instances."
  type        = map(string)
  default     = {}
}

# Cluster settings

variable "domain" {
  description = "Domain name of the cluster (for FQDN definition)"
  type        = string
}

variable "pool_size" {
  description = "Pool size. For HA setup, requires 2 at least"
  type        = number
  default     = 1
}

variable "kubernetes" {
  description = "Kubernetes cluster settings."
  type = object({
    apiserver_url                = string
    apiserver_healthcheck_url    = string
    cluster_domain               = string
    controlplane_ca_pem          = string
    dns_service_ipv4             = string
    dns_service_ipv6             = string
    kubelet_authentication_token = string
    kubelet_ca_pem               = string
  })
}

variable "kubelet_labels" {
  description = "Kubelet labels"
  type        = map(string)
  default     = {}
}

variable "kubelet_taints" {
  description = "Kubelet Taints"
  type = map(object({
    value  = string
    effect = string
  }))
  default = {}
}
