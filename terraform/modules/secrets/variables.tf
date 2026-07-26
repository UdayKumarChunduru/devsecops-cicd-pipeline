variable "snyk_token" {
  type      = string
  sensitive = true
}

variable "jenkins_admin_user" {
  type    = string
  default = "admin"
}
