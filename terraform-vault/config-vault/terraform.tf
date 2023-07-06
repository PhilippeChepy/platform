terraform {
  required_providers {
    exoscale = {
      source = "exoscale/exoscale"
    }
    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.16.0"
    }
  }
}
