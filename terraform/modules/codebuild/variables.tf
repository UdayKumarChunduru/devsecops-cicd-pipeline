variable "ecr_repository_url" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/UdayKumarChunduru/devsecops-cicd-pipeline.git"
}

variable "ecr_repository_arn" {
  type = string
}
