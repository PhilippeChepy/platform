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
  template_name        = "Kubernetes 1.24.0 control plane"
  template_description = "Kubernetes 1.24.0 - Control Plane (minimal Ubuntu 22.04 & Hashicorp Vault 1.10.3)"
  template_username    = "ubuntu"
  ssh_username         = "ubuntu"
}

build {
  sources = ["source.exoscale.base"]

  provisioner "ansible" {
    playbook_file = "./ansible/kube-controlplane.yml"
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
