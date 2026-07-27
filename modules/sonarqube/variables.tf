variable "project_name" {
  description = "Project name for naming resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where SonarQube will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for SonarQube EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for SonarQube. t3.small (2GB RAM) is the minimum that works reliably."
  type        = string
  default     = "t3.small"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR blocks allowed to SSH into SonarQube instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Should be restricted in production
}

variable "sonarqube_version" {
  description = "SonarQube version to deploy"
  type        = string
  default     = "lts"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}
