terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">= 0.38.0"
    }
  }
  experiments = [module_variable_optional_attrs]
}
