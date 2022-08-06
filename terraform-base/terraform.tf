terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.25.0"
    }

    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.40.0"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }

    local = {
      source  = "hashicorp/local"
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
  }
}
