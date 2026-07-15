terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

resource "aws_kms_key" "sns" {
  description             = "kms key for encrypting the devsecops sns alerts topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "sns" {
  name          = "alias/${var.topic_name}-key"
  target_key_id = aws_kms_key.sns.key_id
}

resource "aws_sns_topic" "alerts" {
  name              = var.topic_name
  kms_master_key_id = aws_kms_key.sns.arn
}
