# modules/alb-controller/

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "Needed inside the AWS-published IAM policy JSON for the controller"
  type        = string
}

# --- handed off from modules/eks/ - this is what makes IRSA possible ---
variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  description = "Bare OIDC URL (no https://) - used in the trust policy condition"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the controller's service account lives in"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account this role trusts - must match exactly what's used in the Helm install later"
  type        = string
  default     = "aws-load-balancer-controller"
}
