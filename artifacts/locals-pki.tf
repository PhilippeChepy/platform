data "local_file" "properties_vault_configuration" {
  filename = "${path.module}/../artifacts/properties-vault-configuration.json"
}

locals {
  pki = jsondecode(data.local_file.properties_vault_configuration.content)
}