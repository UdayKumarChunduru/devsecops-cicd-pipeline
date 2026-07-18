variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "state_bucket_name" {
  type    = string
  default = "devsecops-pipeline-tfstate"
}

variable "lock_table_name" {
  type    = string
  default = "devsecops-pipeline-tfstate-lock"
}

variable "replica_region" {
  type    = string
  default = "us-west-2"
}
