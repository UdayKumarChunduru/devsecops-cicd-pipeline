module "vpc" {
  source       = "../../modules/vpc"
  name         = "${var.cluster_name}-vpc"
  cluster_name = var.cluster_name
}

module "eks" {
  source             = "../../modules/eks"
  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "ecr" {
  source          = "../../modules/ecr"
  repository_name = var.ecr_repository_name
}

module "sns" {
  source     = "../../modules/sns"
  topic_name = var.sns_topic_name
}

data "aws_caller_identity" "current" {}

module "iam" {
  source             = "../../modules/iam"
  eks_cluster_arn    = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
  ecr_repository_arn = module.ecr.repository_arn
  oidc_provider_arn  = module.eks.oidc_provider_arn
  sns_topic_arn      = module.sns.topic_arn
}

resource "aws_eks_access_entry" "lambda_remediator" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = module.iam.lambda_role_arn
  kubernetes_groups = ["falco-remediator-group"]
  type              = "STANDARD"
}

resource "aws_eks_access_entry" "jenkins_deploy" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = module.iam.jenkins_user_arn
  kubernetes_groups = ["jenkins-deploy-group"]
  type              = "STANDARD"
}
