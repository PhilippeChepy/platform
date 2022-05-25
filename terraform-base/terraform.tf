terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">=0.35.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">=3.2.0"
    }
  }
}
