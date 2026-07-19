terraform {
  backend "s3" {
    bucket         = "devsecops-pipeline-tfstate-fortecipher"
    key            = "aws/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devsecops-pipeline-tfstate-fortecipher-lock"
    encrypt        = true
  }
}
