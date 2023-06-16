terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.4.0"
    }

    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.49.0"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 3.2.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}
