variable "api_key" {
}

variable "api_secret" {
}

variable "zone" {
}

source "exoscale" "base" {
  api_key              = var.api_key
  api_secret           = var.api_secret
  instance_template    = "Linux Ubuntu 22.04 LTS 64-bit"
  instance_disk_size   = 10
  template_zone        = var.zone
  template_name        = "Vault 1.12.2"
  template_description = "Hashicorp Vault 1.12.2 on top of Ubuntu 22.04"
  template_username    = "ubuntu"
  ssh_username         = "ubuntu"
}

build {
  sources = ["source.exoscale.base"]

  provisioner "ansible" {
    playbook_file   = "./ansible/exoscale-vault.yml"
    user            = "ubuntu"

    ansible_ssh_extra_args = ["-oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedKeyTypes=+ssh-rsa"]
    extra_arguments = [ "--scp-extra-args", "'-O'" ]
  }
}

packer {
  required_plugins {
    exoscale = {
      version = ">= 0.3.0"
      source  = "github.com/exoscale/exoscale"
    }
  }
}
