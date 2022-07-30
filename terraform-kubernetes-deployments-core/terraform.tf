terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.12.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.0"
    }

    vault = {
      source  = "hashicorp/vault"
      version = ">= 3.8.0"
    }
  }
}
