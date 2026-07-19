variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  description = "Email address to receive infrastructure alerts"
  type        = string
}
