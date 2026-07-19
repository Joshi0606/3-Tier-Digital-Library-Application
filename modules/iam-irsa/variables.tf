# modules/iam-irsa/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# --- handed off from modules/eks/ - same OIDC mechanism as alb-controller ---
variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Bare OIDC URL (no https://) - used in trust policy conditions"
  type        = string
}

# --- app pod service account identity ---
variable "app_namespace" {
  description = "Kubernetes namespace the app service accounts live in"
  type        = string
  default     = "default"
}

variable "app_service_account_name" {
  description = "Name of the app's Kubernetes service account - must match exactly what's used in each service's Deployment manifest"
  type        = string
  default     = "digital-library-app"
}

# --- cloudwatch agent service account identity ---
variable "cloudwatch_agent_namespace" {
  type    = string
  default = "amazon-cloudwatch"
}

variable "cloudwatch_agent_service_account_name" {
  type    = string
  default = "cloudwatch-agent"
}

# --- resource ARNs to scope app permissions to (least privilege - never
#     a wildcard across all buckets/queues/secrets in the account) ---
variable "assets_bucket_arn" {
  description = "ARN of the S3 assets bucket - from modules/s3/"
  type        = string
}

variable "orders_queue_arn" {
  description = "ARN of the SQS orders queue - from modules/sqs/"
  type        = string
}

variable "orders_dlq_arn" {
  description = "ARN of the SQS DLQ - from modules/sqs/ (app needs read access to inspect failed messages)"
  type        = string
}

variable "jwt_signing_key_secret_arn" {
  description = "ARN of the JWT signing key secret - from modules/secrets/"
  type        = string
}

variable "rds_master_user_secret_arn" {
  description = "ARN of the AWS-managed RDS master password secret - from modules/rds/"
  type        = string
}
