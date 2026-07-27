output "lambda_role_arn" {
  value = aws_iam_role.lambda_remediation.arn
}

output "falcosidekick_irsa_role_arn" {
  value = module.falcosidekick_irsa.arn
}
