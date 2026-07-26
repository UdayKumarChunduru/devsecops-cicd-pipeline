output "cluster_name" {
  value = module.eks.cluster_name
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

output "instance_id" {
  value = module.compute.instance_id
}

output "codebuild_project_name" {
  value = module.codebuild.project_name
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "lambda_role_arn" {
  value = module.iam.lambda_role_arn
}

output "sns_topic_arn" {
  value = module.sns.topic_arn
}
