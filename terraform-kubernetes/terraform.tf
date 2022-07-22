terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.39.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.7.0"
    }
  }
}
