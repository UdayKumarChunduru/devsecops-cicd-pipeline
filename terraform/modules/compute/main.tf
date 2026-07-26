terraform {
  required_version = ">= 1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_security_group" "alb" {
  name_prefix = "jenkins-alb-sg-"
  vpc_id      = var.vpc_id

  ingress {
    description = "http from github webhook ip ranges only, no other inbound path exists to this alb"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.github_webhook_cidrs
  }

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

resource "aws_security_group" "jenkins" {
  name_prefix = "jenkins-sg-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "jenkins ui from alb only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "sonarqube ui from alb only"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

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

resource "aws_security_group_rule" "efs_from_jenkins" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = var.efs_security_group_id
  source_security_group_id = aws_security_group.jenkins.id
}

resource "aws_iam_role" "jenkins_host" {
  name = "jenkins-host-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.jenkins_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins_host" {
  name = "jenkins-host-policy"
  role = aws_iam_role.jenkins_host.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsReadAll"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          var.jenkins_admin_user_secret_arn,
          var.jenkins_admin_password_secret_arn,
          var.sonar_admin_password_secret_arn,
          var.sonar_token_secret_arn,
          var.snyk_token_secret_arn,
        ]
      },
      {
        Sid      = "SonarTokenWriteOnly"
        Effect   = "Allow"
        Action   = ["secretsmanager:PutSecretValue"]
        Resource = [var.sonar_token_secret_arn]
      },
      {
        Sid      = "SecretsKmsUse"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        Resource = var.secrets_kms_key_arn
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid      = "EksDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid      = "CodeBuildTrigger"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins_host" {
  name = "jenkins-host-profile"
  role = aws_iam_role.jenkins_host.name
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "jenkins_host" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_host.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 40
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tpl", {
    efs_jenkins_id     = var.efs_jenkins_id
    efs_sonarqube_id   = var.efs_sonarqube_id
    efs_maven_id       = var.efs_maven_id
    aws_region         = var.aws_region
    ecr_repository_url = var.ecr_repository_url
  })

  tags = {
    Name    = "jenkins-sonarqube-host"
    project = "devsecops-pipeline"
  }
}

resource "aws_lb" "jenkins" {
  name               = "jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = {
    project = "devsecops-pipeline"
  }
}

resource "aws_lb_target_group" "jenkins" {
  name        = "jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/login"
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_target_group" "sonarqube" {
  name        = "sonarqube-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/sonarqube/api/system/status"
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins_host.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "sonarqube" {
  target_group_arn = aws_lb_target_group.sonarqube.arn
  target_id        = aws_instance.jenkins_host.id
  port             = 9000
}

# checkov:skip=CKV_AWS_2: no owned domain, no acm cert possible without domain ownership validation, alb serves only the github webhook restricted to github's published cidr ranges via security group, not open to 0.0.0.0/0
# checkov:skip=CKV_AWS_103: tls termination requires a validated domain, not available in this environment
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

resource "aws_lb_listener_rule" "sonarqube" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/sonarqube*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.sonarqube.arn
  }
}
