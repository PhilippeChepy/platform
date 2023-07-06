provider "aws" {
  endpoints {
    s3 = "https://sos-${local.specs.backup.zone}.exo.io"
  }

  region = local.specs.backup.zone

  # Skip AWS validations
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "exoscale" {
  timeout = 120
}
