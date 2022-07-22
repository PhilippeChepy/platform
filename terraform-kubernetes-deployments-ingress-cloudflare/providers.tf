provider "cloudflare" {
}

provider "local" {
}

provider "kubernetes" {
  config_path = "${path.module}/../artifacts/admin.kubeconfig"
}

provider "vault" {
  address      = local.vault.url
  token        = data.local_file.root_token.content
  ca_cert_file = "${path.module}/../artifacts/ca-certificate.pem"
}
