# modules/rds/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# --- handed off from modules/vpc/ ---
variable "private_subnet_ids" {
  description = "RDS lives here - same private tier as EKS nodes, isolated by security group not subnet"
  type        = list(string)
}

variable "rds_security_group_id" {
  description = "The SG from modules/vpc/ that only trusts the EKS node SG on port 3306"
  type        = string
}

# --- database config ---
variable "db_name" {
  type    = string
  default = "digitallibrary"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_instance_class" {
  description = "RDS instance size - small for a portfolio project"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Standby replica in a second AZ - costs 2x. Read from a variable (not hardcoded) per README gotcha, so it's easy to toggle."
  type        = bool
  default     = false
}

variable "db_engine_version" {
  type    = string
  default = "8.0"
}
