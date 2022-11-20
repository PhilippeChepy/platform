terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.41.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.11.0"
    }
  }
}
