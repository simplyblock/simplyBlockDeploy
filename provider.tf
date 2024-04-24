provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket         = "simplyblock-terraform-state-bucket"
    key            = "csi"
    region         = "us-east-2"
    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}
