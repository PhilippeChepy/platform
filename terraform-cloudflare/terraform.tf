terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.8.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.16.0"
    }
  }
}
