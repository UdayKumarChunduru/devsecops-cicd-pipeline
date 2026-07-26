terraform {
  required_version = ">= 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "kms key for devsecops-pipeline secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/devsecops-pipeline-secrets-key"
  target_key_id = aws_kms_key.secrets.key_id
}

resource "random_password" "jenkins_admin" {
  length           = 24
  special          = true
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@%^&*_-+="
}

resource "random_password" "sonar_admin" {
  length           = 24
  special          = true
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!@%^&*_-+="
}

resource "aws_secretsmanager_secret" "jenkins_admin_user" {
  name       = "devsecops-pipeline/jenkins-admin-user"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "jenkins_admin_user" {
  secret_id     = aws_secretsmanager_secret.jenkins_admin_user.id
  secret_string = var.jenkins_admin_user
}

resource "aws_secretsmanager_secret" "jenkins_admin_password" {
  name       = "devsecops-pipeline/jenkins-admin-password"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "jenkins_admin_password" {
  secret_id     = aws_secretsmanager_secret.jenkins_admin_password.id
  secret_string = random_password.jenkins_admin.result
}

resource "aws_secretsmanager_secret" "sonar_admin_password" {
  name       = "devsecops-pipeline/sonar-admin-password"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "sonar_admin_password" {
  secret_id     = aws_secretsmanager_secret.sonar_admin_password.id
  secret_string = random_password.sonar_admin.result
}

resource "aws_secretsmanager_secret" "snyk_token" {
  name       = "devsecops-pipeline/snyk-token"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "snyk_token" {
  secret_id     = aws_secretsmanager_secret.snyk_token.id
  secret_string = var.snyk_token
}

resource "aws_secretsmanager_secret" "sonar_token" {
  name       = "devsecops-pipeline/sonar-token"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "sonar_token" {
  secret_id     = aws_secretsmanager_secret.sonar_token.id
  secret_string = "placeholder-populated-after-sonarqube-boots"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
