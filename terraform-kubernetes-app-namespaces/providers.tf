provider "kubernetes" {
  config_path = "${path.module}/../artifacts/admin.kubeconfig"
}

provider "local" {
}
