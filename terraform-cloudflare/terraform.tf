terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 3.30.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.12.0"
    }
  }
}
