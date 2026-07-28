terraform {
  backend "s3" {
    bucket       = "digital-library-tfstate-519111080498"
    key          = "digital-library/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
