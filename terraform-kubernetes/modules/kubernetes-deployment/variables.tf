variable "kubeconfig_path" {
  description = "Path to Kubernetes client configuration file (kubeconfig)."
  type        = string
}

variable "deployment_namespace" {
  type = string
}

variable "deployment_manifest_file" {
  description = "The deployment manifest yaml document path."
  type        = string
}

variable "deployment_variables" {
  description = "A map of variables to be replaced from manifests (key = placeholder, value = replacement value)."
  type        = map(string)
}

variable "templated" {
  description = "Specify if the manifest is templated or not."
  type        = bool
}

variable "readiness_checks" {
  description = "A set of defining readiness checks which needs to be valid to consider the resource as created."
  type = set(object({
    mode      = optional(string)
    kind      = string
    timeout   = optional(string)
    name      = string
    condition = optional(string)      # mode=wait
    labels    = optional(set(string)) # mode=wait
  }))
  default = []
}

variable "service_account_tokens" {
  description = "A map of service account tokens to be created in addition of the deployment (key = name, value = service account)."
  type        = map(object({ service_account = string }))
  default     = {}
}