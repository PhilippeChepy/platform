terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.46.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.13.0"
    }
  }
}
