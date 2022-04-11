variable "api_key" {
}

variable "api_secret" {
}

variable "zone" {
}

source "exoscale" "base" {
  api_key              = var.api_key
  api_secret           = var.api_secret
  instance_template    = "Linux Ubuntu 20.04 LTS 64-bit"
  instance_disk_size   = 10
  template_zone        = var.zone
  template_name        = "Vault 1.10.0"
  template_description = "Hashicorp Vault 1.10.0 on top of Ubuntu 20.04"
  template_username    = "ubuntu"
  ssh_username         = "ubuntu"
}

build {
  sources = ["source.exoscale.base"]

  provisioner "ansible" {
    playbook_file = "./ansible/vault.yml"
    user          = "ubuntu"
  }
}

packer {
  required_plugins {
    exoscale = {
      version = ">= 0.1.3"
      source  = "github.com/exoscale/exoscale"
    }
  }
}
