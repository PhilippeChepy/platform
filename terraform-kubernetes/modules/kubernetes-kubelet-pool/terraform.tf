terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = ">=0.32.0"
    }
  }
  experiments = [module_variable_optional_attrs]
}
