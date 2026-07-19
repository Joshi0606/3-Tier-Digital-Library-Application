variable "project_name" {
  description = "Project name, used for naming and tagging resources"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. prod, dev)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create (one per microservice)"
  type        = list(string)
  default     = ["auth", "book", "borrow", "frontend", "worker"]
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten (MUTABLE) or not (IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Whether to automatically scan images for vulnerabilities when pushed"
  type        = bool
  default     = true
}
