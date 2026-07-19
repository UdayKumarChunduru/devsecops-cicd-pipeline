output "lambda_role_arn" {
  value = aws_iam_role.lambda_remediation.arn
}

output "jenkins_user_arn" {
  value = aws_iam_user.jenkins.arn
}

output "jenkins_access_key_id" {
  value = aws_iam_access_key.jenkins.id
}

output "jenkins_secret_access_key" {
  value     = aws_iam_access_key.jenkins.secret
  sensitive = true
}

output "falcosidekick_irsa_role_arn" {
  value = module.falcosidekick_irsa.arn
}
