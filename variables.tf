# variables.tf (root)
# Declares every variable referenced in root main.tf. Most just pass
# straight through to a module of the same name below - actual values
# live in terraform.tfvars (next file), not here.

variable "project_name" {
  description = "Short name used as a prefix for every resource across all modules"
  type        = string
  default     = "digital-library"
}

variable "environment" {
  description = "Environment name, e.g. 'prod' or 'dev'"
  type        = string
  default     = "prod"
}

# --- passed to modules/vpc/ ---
variable "vpc_cidr" {
  description = "IP address range for the whole VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Which AWS Availability Zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "nat_gateway_count" {
  description = "How many NAT Gateways (1 = cheaper/shared, 2 = one per AZ/more resilient)"
  type        = number
  default     = 1
}

variable "alb_target_ports" {
  description = "Real container ports the ALB Controller sends traffic to directly"
  type        = list(number)
  default     = [80, 5001, 5002, 5003]
}

# --- passed to modules/s3/ ---
variable "assets_bucket_suffix" {
  description = "Suffix appended to the assets bucket name for global S3 uniqueness - set a real value in terraform.tfvars, no safe default exists"
  type        = string
}

# --- passed to modules/sns/ ---
variable "alert_email" {
  description = "List of email addresses to receive infrastructure alerts - set in terraform.tfvars, deliberately no default since it's personal data"
  type        = list(string)
}

# --- passed to modules/rds/ ---
variable "db_multi_az" {
  description = "Whether RDS runs a standby replica in a second AZ (costs 2x) - false for this project, kept as a variable so it's easy to toggle"
  type        = bool
  default     = false
}
