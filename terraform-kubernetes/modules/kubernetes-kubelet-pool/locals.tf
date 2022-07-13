locals {
  kubelet_labels = join(",", [
    for key, value in var.kubelet_labels : "${key}=${value}"
  ])
}
