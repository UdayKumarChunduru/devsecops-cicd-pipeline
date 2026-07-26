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
  description = "alb accepting only github webhook traffic"

  ingress {
    description = "http from github webhook ip ranges only, no other inbound path exists to this alb"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.github_webhook_cidrs
  }

  egress {
    description = "forward to jenkins target group inside the vpc only"
    from_port   = 8080
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  tags = {
    project = "devsecops-pipeline"
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

resource "aws_security_group" "jenkins" {
  name_prefix = "jenkins-sg-"
  vpc_id      = var.vpc_id
  description = "jenkins and sonarqube host, alb ingress only, https egress only"

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
    description = "https to aws apis, ecr, s3, github and codebuild, all reachable only over 443"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "dns resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    project = "devsecops-pipeline"
  }
}

resource "aws_security_group_rule" "efs_from_jenkins" {
  description              = "nfs from the jenkins host to the shared efs volumes"
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
        # checkov:skip=CKV_AWS_355:ecr:GetAuthorizationToken is account level, aws does not support a resource arn constraint for this specific action
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
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
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds", "codebuild:StopBuild"]
        Resource = "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:project/devsecops-image-build"
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
  monitoring             = true
  ebs_optimized          = true

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

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "devsecops-pipeline-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    id     = "expire-old-alb-logs"
    status = "Enabled"
    expiration {
      days = 90
    }
  }
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}

# checkov:skip=CKV_AWS_150:deletion protection would block terraform destroy during teardown, this environment is torn down and recreated regularly by design
resource "aws_lb" "jenkins" {
  name                       = "jenkins-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  tags = {
    project = "devsecops-pipeline"
  }
}

# checkov:skip=CKV_AWS_378:traffic between the alb and this target stays inside the vpc private subnet, jenkins itself does not terminate tls, adding tls here would require a self managed cert on the instance for no real security gain within a private network path
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

# checkov:skip=CKV_AWS_378:same reasoning as the jenkins target group, internal vpc path only
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
