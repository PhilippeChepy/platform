provider "aws" {
  alias = "sos"

  endpoints {
    s3 = "https://sos-${local.platform_backup_zone}.exo.io"
  }

  region = local.platform_backup_zone

  # Skip AWS validations
  skip_credentials_validation = true
  skip_get_ec2_platforms      = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "exoscale" {
  timeout = 120
}

provider "random" {
}

provider "tls" {
}