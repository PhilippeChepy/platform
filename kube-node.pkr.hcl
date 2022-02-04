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
  template_name        = "Kubernetes 1.23.3 node"
  template_description = "Kubernetes 1.23.3 node components (minimal Ubuntu 20.04)"
  template_username    = "ubuntu"
  ssh_username         = "ubuntu"
}

build {
  sources = ["source.exoscale.base"]

  provisioner "ansible" {
    playbook_file = "./ansible/kube-node.yml"
    user          = "ubuntu"
  }
}

packer {
  required_plugins {
    exoscale = {
      version = ">= 0.1.2"
      source  = "github.com/exoscale/exoscale"
    }
  }
}