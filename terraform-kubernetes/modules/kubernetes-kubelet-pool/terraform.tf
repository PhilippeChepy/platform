terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.39.0"
    }
  }
  experiments = [module_variable_optional_attrs]
}
