output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "sns_topic_arn" {
  value = module.sns.topic_arn
}

output "lambda_role_arn" {
  value = module.iam.lambda_role_arn
}

output "jenkins_access_key_id" {
  value = module.iam.jenkins_access_key_id
}

output "jenkins_secret_access_key" {
  value     = module.iam.jenkins_secret_access_key
  sensitive = true
}

output "falcosidekick_irsa_role_arn" {
  value = module.iam.falcosidekick_irsa_role_arn
}

output "aws_region" {
  value = var.aws_region
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
