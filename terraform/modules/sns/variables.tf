variable "topic_name" {
  type        = string
  description = "Name of the SNS topic for security alerts"
  default     = "devsecops-pipeline-alerts"
}

variable "alert_email" {
  type        = string
  description = "Email address to receive SNS security alert notifications"
}
