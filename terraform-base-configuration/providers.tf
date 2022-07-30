provider "exoscale" {
}

provider "local" {
}

provider "random" {
}

provider "tls" {
}

provider "vault" {
  address      = local.vault.url
  token        = local.vault.token
  ca_cert_file = "${path.module}/../artifacts/ca-certificate.pem"
}
