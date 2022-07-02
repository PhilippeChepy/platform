terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.38.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.4.0"
    }
  }
}
