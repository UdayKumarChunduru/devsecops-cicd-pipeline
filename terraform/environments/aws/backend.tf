terraform {
  backend "s3" {
    bucket         = "devsecops-pipeline-tfstate"
    key            = "aws/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "devsecops-pipeline-tfstate-lock"
    encrypt        = true
  }
}
