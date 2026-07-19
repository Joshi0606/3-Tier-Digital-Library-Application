variable "project_name" {
  description = "Project name, used for naming and tagging resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. prod, dev)"
  type        = string
}

variable "assets_bucket_suffix" {
  description = "Suffix appended to bucket name to guarantee global uniqueness (S3 bucket names are globally unique across ALL AWS accounts, not just yours)"
  type        = string
}

variable "versioning_enabled" {
  description = "Whether to enable versioning on the assets bucket"
  type        = bool
  default     = true
}
