variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "efs_jenkins_id" {
  type = string
}

variable "efs_sonarqube_id" {
  type = string
}

variable "efs_maven_id" {
  type = string
}

variable "efs_security_group_id" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "secrets_kms_key_arn" {
  type = string
}

variable "jenkins_admin_user_secret_arn" {
  type = string
}

variable "jenkins_admin_password_secret_arn" {
  type = string
}

variable "sonar_admin_password_secret_arn" {
  type = string
}

variable "sonar_token_secret_arn" {
  type = string
}

variable "snyk_token_secret_arn" {
  type = string
}

variable "github_webhook_cidrs" {
  type    = list(string)
  default = ["140.82.112.0/20", "143.55.64.0/20", "185.199.108.0/22", "192.30.252.0/22"]
}
