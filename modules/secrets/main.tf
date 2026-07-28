# JWT Signing Key

resource "random_password" "jwt_signing_key" {
  length  = var.jwt_key_length
  special = true
}

resource "aws_secretsmanager_secret" "jwt_signing_key" {
  name                    = "${var.project_name}-${var.environment}-jwt-signing-key"
  recovery_window_in_days = var.recovery_window_days

  tags = {
    Name = "${var.project_name}-${var.environment}-jwt-signing-key"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_signing_key" {
  secret_id     = aws_secretsmanager_secret.jwt_signing_key.id
  secret_string = random_password.jwt_signing_key.result
}
