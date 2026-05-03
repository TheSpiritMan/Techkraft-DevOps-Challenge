terraform {
  backend "s3" {
    bucket       = "techkraft-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}