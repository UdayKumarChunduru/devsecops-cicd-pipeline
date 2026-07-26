terraform {
  backend "s3" {
    bucket       = "devsecops-pipeline-tfstate-fortecipher"
    key          = "aws-cloud/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
