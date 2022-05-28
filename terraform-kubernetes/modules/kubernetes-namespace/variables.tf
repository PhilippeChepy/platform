variable "kubeconfig_path" {
  description = "Path to Kubernetes client configuration file (kubeconfig)."
  type        = string
}

variable "namespace" {
  description = "Name of the namespace to manage"
  type        = string
}