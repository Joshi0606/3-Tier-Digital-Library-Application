variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_version" {
  description = "Kubernetes version - 1.31 (1.29 was already deprecated per README)"
  type        = string
  default     = "1.31"
}

# --- Inputs handed off FROM the vpc module (this is module interconnection) ---
variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Control plane ENIs also live across public+private subnets for redundancy"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Worker nodes launch here - no public IPs"
  type        = list(string)
}

variable "eks_nodes_security_group_id" {
  description = "The SG we built in vpc module (ALB->pods, node-to-node rules)"
  type        = string
}

# --- Inputs handed off FROM the iam module ---
variable "eks_cluster_role_arn" {
  type = string
}

variable "eks_node_role_arn" {
  type = string
}

# --- Node group sizing ---
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]   # t3.medium had no capacity in us-east-1a/1b per README
}

variable "node_desired_size" {
  type    = number
  default = 2    # updated per user request - 2 nodes for HA across 2 AZs
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "oidc_thumbprint_list" {
  description = "Thumbprint list for the EKS OIDC provider. AWS now manages this automatically - pass an empty list and AWS will populate it."
  type        = list(string)
  default     = []
}
