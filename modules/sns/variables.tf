variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  description = "List of email addresses to receive infrastructure alerts"
  type        = list(string)
}
