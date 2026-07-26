output "project_name" {
  value = aws_codebuild_project.image_build.name
}

output "role_arn" {
  value = aws_iam_role.codebuild.arn
}
