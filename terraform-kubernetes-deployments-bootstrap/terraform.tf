terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.12.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.8.0"
    }
  }
}
