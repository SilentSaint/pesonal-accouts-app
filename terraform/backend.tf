terraform {
  backend "s3" {
    bucket       = "automatic-expense-tracker-terraform-state-727118420276"
    key          = "production/terraform.tfstate"
    region       = "ap-south-2"
    encrypt      = true
    use_lockfile = true
  }
}
