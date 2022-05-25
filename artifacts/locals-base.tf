data "local_file" "root_ca_certificate_pem" {
  filename = "${path.module}/../artifacts/ca-certificate.pem"
}

data "local_sensitive_file" "root_ca_private_key_pem" {
  filename = "${path.module}/../artifacts/ca-certificate.key"
}

data "local_file" "properties_base" {
  filename = "${path.module}/../artifacts/properties-base.json"
}

data "local_file" "properties_vault" {
  filename = "${path.module}/../artifacts/properties-vault.json"
}

data "local_file" "root_token" {
  filename = "${path.module}/../artifacts/root-token.txt"
}

locals {
  base  = jsondecode(data.local_file.properties_base.content)
  vault = merge(jsondecode(data.local_file.properties_vault.content), { token = data.local_file.root_token.content })
}