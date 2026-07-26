output "kms_key_arn" {
  value = aws_kms_key.secrets.arn
}

output "jenkins_admin_user_arn" {
  value = aws_secretsmanager_secret.jenkins_admin_user.arn
}

output "jenkins_admin_password_arn" {
  value = aws_secretsmanager_secret.jenkins_admin_password.arn
}

output "sonar_admin_password_arn" {
  value = aws_secretsmanager_secret.sonar_admin_password.arn
}

output "sonar_token_arn" {
  value = aws_secretsmanager_secret.sonar_token.arn
}

output "snyk_token_arn" {
  value = aws_secretsmanager_secret.snyk_token.arn
}
