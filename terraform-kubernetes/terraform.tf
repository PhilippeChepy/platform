terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.38.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.7.0"
    }
  }
}
