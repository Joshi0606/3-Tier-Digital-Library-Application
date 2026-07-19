# modules/ssm/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# Map of service name -> ECR repository URL, straight from modules/ecr/'s
# repository_urls output. Turned into individual SSM parameters below so
# CI/CD and kubectl manifests can look up "which image do I deploy for
# the auth service" without hardcoding account IDs anywhere.
variable "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL (from modules/ecr/)"
  type        = map(string)
}

# Generic bucket for any other config values you want in SSM as plain
# (non-secret) parameters - e.g. EKS cluster name, RDS endpoint, S3 bucket
# name. Kept as a flexible map so this module doesn't need a new variable
# every time you want to expose one more config value.
variable "additional_parameters" {
  description = "Map of extra config key -> value to store as SSM parameters (non-secret config only - use modules/secrets/ for anything sensitive)"
  type        = map(string)
  default     = {}
}
