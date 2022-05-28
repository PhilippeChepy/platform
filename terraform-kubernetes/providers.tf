provider "exoscale" {
  timeout = 240
}

provider "vault" {
  address      = local.vault_settings.url
  token        = data.local_file.root_token.content
  ca_cert_file = "${path.module}/../artifacts/ca-certificate.pem"
}
