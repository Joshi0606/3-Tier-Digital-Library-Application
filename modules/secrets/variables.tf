# modules/secrets/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

# How many days AWS keeps a deleted secret recoverable before permanently
# purging it. 0 = delete immediately (useful in early dev so you can
# re-apply/re-destroy without waiting); 7-30 is the safer prod default.
variable "recovery_window_days" {
  description = "Days a deleted secret stays recoverable before permanent purge (0 = immediate delete)"
  type        = number
  default     = 0
}

# Length of the generated JWT signing key. 64 chars gives strong entropy
# for HMAC-based JWT signing (e.g. HS256) without being unwieldy.
variable "jwt_key_length" {
  description = "Character length of the generated JWT signing key"
  type        = number
  default     = 64
}
