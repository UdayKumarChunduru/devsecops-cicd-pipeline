variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "devsecops-real"
}

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "ecr_repository_name" {
  type    = string
  default = "demo-service"
}

variable "sns_topic_name" {
  type    = string
  default = "devsecops-pipeline-alerts"
}
