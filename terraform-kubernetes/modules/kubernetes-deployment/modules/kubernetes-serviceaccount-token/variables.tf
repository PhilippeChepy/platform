variable "kubeconfig_path" {
  description = "Path to Kubernetes client configuration file (kubeconfig)."
  type        = string
}

variable "name" {
  description = "Name of the token"
  type        = string
}

variable "namespace" {
  description = "Namespace of the token"
  type        = string
}

variable "service_account" {
  description = "Target service account"
  type        = string
}