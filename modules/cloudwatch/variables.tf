# modules/cloudwatch/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# --- handed off from modules/sns/ ---
variable "sns_topic_arn" {
  description = "ARN of the alerts topic - every alarm below notifies here"
  type        = string
}

# --- handed off from modules/eks/ ---
variable "node_group_asg_name" {
  description = "ASG backing the EKS managed node group - used for the CPU alarm dimension"
  type        = string
}

# --- handed off from modules/rds/ ---
variable "db_instance_id" {
  description = "RDS instance identifier - used for the RDS alarm dimensions"
  type        = string
}

# --- handed off from modules/sqs/ ---
variable "orders_dlq_name" {
  description = "DLQ name - used for the DLQ depth alarm dimension"
  type        = string
}

# --- alarm thresholds (kept as variables, not hardcoded, so they're easy
#     to tune later without touching main.tf - same principle as db_multi_az) ---
variable "ec2_cpu_threshold" {
  type    = number
  default = 80
}

variable "rds_cpu_threshold" {
  type    = number
  default = 80
}

# RDS free storage alarm fires BELOW this many bytes (5GB, converted since
# CloudWatch's FreeStorageSpace metric is reported in bytes, not GB).
variable "rds_free_storage_threshold_bytes" {
  description = "Alarm fires when RDS free storage drops below this many bytes (default 5GB)"
  type        = number
  default     = 5368709120 # 5 * 1024^3
}

# How many app service log groups to create - one per microservice, so
# each service's logs are isolated and easy to find/filter individually.
variable "app_services" {
  description = "List of app service names to create log groups for"
  type        = list(string)
  default     = ["auth", "book", "borrow", "frontend", "worker"]
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps app logs before deleting them"
  type        = number
  default     = 14
}
