terraform {
  required_version = ">= 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

resource "aws_kms_key" "efs" {
  description             = "kms key for jenkins, sonarqube and maven efs volumes"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "efs" {
  name          = "alias/devsecops-pipeline-efs-key"
  target_key_id = aws_kms_key.efs.key_id
}

resource "aws_security_group" "efs" {
  name_prefix = "devsecops-efs-sg-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    project = "devsecops-pipeline"
  }
}

resource "aws_efs_file_system" "jenkins_home" {
  creation_token  = "devsecops-jenkins-home"
  encrypted       = true
  kms_key_id      = aws_kms_key.efs.arn
  throughput_mode = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name    = "devsecops-jenkins-home"
    project = "devsecops-pipeline"
  }
}

resource "aws_efs_mount_target" "jenkins_home" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.jenkins_home.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_file_system" "sonarqube_data" {
  creation_token  = "devsecops-sonarqube-data"
  encrypted       = true
  kms_key_id      = aws_kms_key.efs.arn
  throughput_mode = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name    = "devsecops-sonarqube-data"
    project = "devsecops-pipeline"
  }
}

resource "aws_efs_mount_target" "sonarqube_data" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.sonarqube_data.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_file_system" "maven_repo" {
  creation_token  = "devsecops-maven-repo"
  encrypted       = true
  kms_key_id      = aws_kms_key.efs.arn
  throughput_mode = "bursting"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name    = "devsecops-maven-repo"
    project = "devsecops-pipeline"
  }
}

resource "aws_efs_mount_target" "maven_repo" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.maven_repo.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
