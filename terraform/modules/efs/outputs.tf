output "jenkins_home_id" {
  value = aws_efs_file_system.jenkins_home.id
}

output "sonarqube_data_id" {
  value = aws_efs_file_system.sonarqube_data.id
}

output "maven_repo_id" {
  value = aws_efs_file_system.maven_repo.id
}

output "efs_security_group_id" {
  value = aws_security_group.efs.id
}
