data "aws_caller_identity" "current" {}

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

module "iam" {
  source             = "../../modules/iam"
  eks_cluster_arn    = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
  ecr_repository_arn = module.ecr.repository_arn
  oidc_provider_arn  = module.eks.oidc_provider_arn
  sns_topic_arn      = module.sns.topic_arn
  sns_kms_key_arn    = module.sns.kms_key_arn
}

module "efs" {
  source             = "../../modules/efs"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "secrets" {
  source     = "../../modules/secrets"
  snyk_token = var.snyk_token
}

module "codebuild" {
  source             = "../../modules/codebuild"
  ecr_repository_url = module.ecr.repository_url
  aws_region         = var.aws_region
  github_repo_url    = "https://github.com/${var.github_org_repo}.git"
}

module "compute" {
  source                             = "../../modules/compute"
  vpc_id                             = module.vpc.vpc_id
  public_subnet_ids                  = module.vpc.public_subnet_ids
  private_subnet_ids                 = module.vpc.private_subnet_ids
  efs_jenkins_id                     = module.efs.jenkins_home_id
  efs_sonarqube_id                   = module.efs.sonarqube_data_id
  efs_maven_id                       = module.efs.maven_repo_id
  efs_security_group_id              = module.efs.efs_security_group_id
  ecr_repository_url                 = module.ecr.repository_url
  aws_region                         = var.aws_region
  cluster_name                       = module.eks.cluster_name
  secrets_kms_key_arn                = module.secrets.kms_key_arn
  jenkins_admin_user_secret_arn      = module.secrets.jenkins_admin_user_arn
  jenkins_admin_password_secret_arn  = module.secrets.jenkins_admin_password_arn
  sonar_admin_password_secret_arn    = module.secrets.sonar_admin_password_arn
  sonar_token_secret_arn             = module.secrets.sonar_token_arn
  snyk_token_secret_arn              = module.secrets.snyk_token_arn
}

module "budget" {
  source            = "../../modules/budget"
  monthly_limit_usd = var.budget_monthly_limit_usd
  alert_email       = var.budget_alert_email
}

resource "aws_eks_access_entry" "lambda_remediator" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = module.iam.lambda_role_arn
  kubernetes_groups = ["falco-remediator-group"]
  type              = "STANDARD"
}

resource "aws_eks_access_entry" "jenkins_host" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/jenkins-host-role"
  kubernetes_groups = ["jenkins-deploy-group"]
  type              = "STANDARD"
  depends_on        = [module.compute]
}
