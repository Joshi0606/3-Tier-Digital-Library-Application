terraform {
  backend "s3" {
    bucket       = "ak2.kops"
    key          = "digital-library/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
