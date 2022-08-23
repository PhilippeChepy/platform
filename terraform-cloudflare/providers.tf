provider "cloudflare" {
}

provider "local" {
}

provider "vault" {
  address      = local.vault.url
  token        = data.local_file.root_token.content
  ca_cert_file = "${path.module}/../artifacts/ca-certificate.pem"
}
