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

variable "codeconnection_arn" {
  type        = string
  description = "ARN of the Available AWS CodeConnection for GitHub"
}
