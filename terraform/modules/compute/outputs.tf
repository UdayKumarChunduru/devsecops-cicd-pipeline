output "alb_dns_name" {
  value = aws_lb.jenkins.dns_name
}

output "instance_id" {
  value = aws_instance.jenkins_host.id
}
