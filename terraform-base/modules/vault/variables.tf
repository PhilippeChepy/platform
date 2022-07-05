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
  description = "Service offering of member instances. `standard.tiny` should be sufficient for small infrastructures."
  type        = string
  default     = "standard.tiny"
}

variable "disk_size" {
  description = "Size of the root partition in GB. `10` should be sufficient for most use case."
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

variable "admin_security_groups" {
  description = "A map (key => ID) of security groups authorized to access SSH"
  type        = map(string)
  default     = {}
}

variable "client_security_groups" {
  description = "A map (key => ID) of security groups authorized to access Vault. Clients of the cluster can be authorized using this variable."
  type        = map(string)
  default     = {}
}

variable "ssh_key" {
  description = "Authorized SSH key name."
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

variable "cluster_size" {
  description = "Cluster size. Recommended values are 3 or 5 (tolerates respectively 1 or 2 failure)"
  type        = number
  default     = 3
}

variable "backup" {
  description = "Backup target (S3 bucket and zone)"
  type = object({
    bucket = string
    zone   = string
  })
}