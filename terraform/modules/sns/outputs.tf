output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "topic_name" {
  value = aws_sns_topic.alerts.name
}

output "kms_key_arn" {
  value = aws_kms_key.sns.arn
}
