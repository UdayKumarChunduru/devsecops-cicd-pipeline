terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_remediation" {
  name               = "falco-remediation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_remediation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_eks_describe" {
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "lambda_eks_describe" {
  name   = "eks-describe-cluster"
  role   = aws_iam_role.lambda_remediation.id
  policy = data.aws_iam_policy_document.lambda_eks_describe.json
}

module "falcosidekick_irsa" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-role-for-service-accounts?ref=5b962b1163790398605f2b17447cf5b6cc512237"

  name = "falcosidekick-irsa-role"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["falco:falcosidekick"]
    }
  }

  policies = {
    sns_publish = aws_iam_policy.falcosidekick_sns_publish.arn
  }
}

data "aws_iam_policy_document" "falcosidekick_sns_publish" {
  statement {
    sid       = "PublishToDevsecopsAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  statement {
    sid       = "UseSnsTopicKmsKey"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.sns_kms_key_arn]
  }
}

resource "aws_iam_policy" "falcosidekick_sns_publish" {
  name   = "falcosidekick-sns-publish"
  policy = data.aws_iam_policy_document.falcosidekick_sns_publish.json
}
