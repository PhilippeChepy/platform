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
  default     = false
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

variable "client_security_groups" {
  description = "A map (key => ID) of security groups authorized to access API server. Clients of the cluster can be authorized using this variable."
  type        = map(string)
  default     = {}
}

variable "healthcheck_security_groups" {
  description = "A map (key => ID) of security groups authorized to access API server healthcheck port."
  type        = map(string)
  default     = {}
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

variable "cluster_size" {
  description = "Cluster size. For HA setup, requires 2 at least"
  type        = number
  default     = 2
}

variable "vault" {
  type = object({
    ca_certificate_pem = string
    cluster_name       = string
    healthcheck_url    = string
    url                = string
  })
}

variable "etcd" {
  description = "Settings related to etcd, for use by the API Server as storage backend for the cluster state."
  type = object({
    address         = string
    healthcheck_url = string
  })
}

variable "kubernetes" {
  description = "Control plane internal settings."
  type = object({
    apiserver_service_ipv4 = string
    bootstrap_token_id     = string
    bootstrap_token_secret = string
    cluster_domain         = string
    pod_cidr_ipv4          = string
    pod_cidr_ipv6          = string
    service_cidr_ipv4      = string
    service_cidr_ipv6      = string
  })
}

variable "oidc" {
  description = "OIDC configuration"
  type = object({
    issuer_url = string
    client_id  = string
    claim = object({
      username = string
      groups   = string
    })
  })
}

variable "endpoint_loadbalancer_id" {
  description = "The ID of the infrastructure load balancer"
  type        = string
}
