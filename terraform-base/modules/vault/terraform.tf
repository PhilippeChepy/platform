terraform {
  required_providers {
    exoscale = {
      # source = "terraform.local/local/exoscale"
      source  = "exoscale/exoscale"
      version = ">=0.35.0"
    }
  }
}