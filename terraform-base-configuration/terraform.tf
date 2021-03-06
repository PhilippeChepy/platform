terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.40.0"
    }

    local = {
      source = "hashicorp/local"
      version = ">= 2.2.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.3.2"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.8.0"
    }
  }
}
