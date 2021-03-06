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

    null = {
      source = "hashicorp/null"
      version = ">= 3.1.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.8.0"
    }
  }
}
