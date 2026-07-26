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

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "secrets" {
  description             = "kms key for devsecops-pipeline secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerUse"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
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

# checkov:skip=CKV2_AWS_57:automatic rotation would need a custom lambda rotation function per secret type, jenkins/sonarqube admin passwords and tokens here are rotated by re-running terraform apply or the ec2 user data script, not on an aws managed rotation schedule, this is a demo pipeline credential not a long lived production database credential
resource "aws_secretsmanager_secret" "jenkins_admin_user" {
  name       = "devsecops-pipeline/jenkins-admin-user"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "jenkins_admin_user" {
  secret_id     = aws_secretsmanager_secret.jenkins_admin_user.id
  secret_string = var.jenkins_admin_user
}

# checkov:skip=CKV2_AWS_57:automatic rotation would need a custom lambda rotation function per secret type, jenkins/sonarqube admin passwords and tokens here are rotated by re-running terraform apply or the ec2 user data script, not on an aws managed rotation schedule, this is a demo pipeline credential not a long lived production database credential
resource "aws_secretsmanager_secret" "jenkins_admin_password" {
  name       = "devsecops-pipeline/jenkins-admin-password"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "jenkins_admin_password" {
  secret_id     = aws_secretsmanager_secret.jenkins_admin_password.id
  secret_string = random_password.jenkins_admin.result
}

# checkov:skip=CKV2_AWS_57:automatic rotation would need a custom lambda rotation function per secret type, jenkins/sonarqube admin passwords and tokens here are rotated by re-running terraform apply or the ec2 user data script, not on an aws managed rotation schedule, this is a demo pipeline credential not a long lived production database credential
resource "aws_secretsmanager_secret" "sonar_admin_password" {
  name       = "devsecops-pipeline/sonar-admin-password"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "sonar_admin_password" {
  secret_id     = aws_secretsmanager_secret.sonar_admin_password.id
  secret_string = random_password.sonar_admin.result
}

# checkov:skip=CKV2_AWS_57:automatic rotation would need a custom lambda rotation function per secret type, jenkins/sonarqube admin passwords and tokens here are rotated by re-running terraform apply or the ec2 user data script, not on an aws managed rotation schedule, this is a demo pipeline credential not a long lived production database credential
resource "aws_secretsmanager_secret" "snyk_token" {
  name       = "devsecops-pipeline/snyk-token"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "snyk_token" {
  secret_id     = aws_secretsmanager_secret.snyk_token.id
  secret_string = var.snyk_token
}

# checkov:skip=CKV2_AWS_57:automatic rotation would need a custom lambda rotation function per secret type, jenkins/sonarqube admin passwords and tokens here are rotated by re-running terraform apply or the ec2 user data script, not on an aws managed rotation schedule, this is a demo pipeline credential not a long lived production database credential
resource "aws_secretsmanager_secret" "sonar_token" {
  name       = "devsecops-pipeline/sonar-token"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_secretsmanager_secret_version" "sonar_token" {
  secret_id = aws_secretsmanager_secret.sonar_token.id
  # checkov:skip=CKV_SECRET_6:this is a literal placeholder string, not a real secret, the real value is written by the ec2 user data script after sonarqube generates it, lifecycle ignore_changes below prevents terraform from ever seeing or storing the real value in state
  secret_string = "unset-placeholder-value-see-user-data-script"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
