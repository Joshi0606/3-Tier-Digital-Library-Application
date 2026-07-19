# modules/secrets/main.tf

# ---------------------------------------------------------------------------
# 1. GENERATE THE JWT SIGNING KEY - a random string, generated once by
#    Terraform and stored in its state. This is DIFFERENT from the RDS
#    password: there's no AWS service that auto-generates and rotates a
#    JWT key for you, so Terraform has to create the actual value here.
#    Marked sensitive so it never prints in plan/apply output or logs.
# ---------------------------------------------------------------------------
resource "random_password" "jwt_signing_key" {
  length  = var.jwt_key_length
  special = true
}

# ---------------------------------------------------------------------------
# 2. THE SECRET CONTAINER - just registers a named secret in Secrets
#    Manager. Doesn't hold a value yet; that's a separate resource below
#    (this split mirrors how the AWS API itself works: create the secret,
#    then write a version into it).
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name                    = "${var.project_name}-${var.environment}-jwt-signing-key"
  recovery_window_in_days = var.recovery_window_days

  tags = {
    Name = "${var.project_name}-${var.environment}-jwt-signing-key"
  }
}

# ---------------------------------------------------------------------------
# 3. THE SECRET VALUE - writes the actual generated key into the secret
#    container above. App pods (via IRSA in modules/iam-irsa/, coming up
#    next) will call GetSecretValue on this secret's ARN at runtime to
#    read the key - never hardcoded in app code or a config file.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret_version" "jwt_signing_key" {
  secret_id     = aws_secretsmanager_secret.jwt_signing_key.id
  secret_string = random_password.jwt_signing_key.result
}
