# modules/secrets/outputs.tf

# Secret ARN - needed for IAM policies (modules/iam-irsa/ will scope app
# pod permissions to "secretsmanager:GetSecretValue on THIS secret",
# not every secret in the account).
output "jwt_signing_key_secret_arn" {
  description = "ARN of the JWT signing key secret - used in IAM policies and app runtime config"
  value       = aws_secretsmanager_secret.jwt_signing_key.arn
}

# Secret name - some AWS SDKs/CLI calls accept either name or ARN; having
# both available avoids re-deriving one from the other downstream.
output "jwt_signing_key_secret_name" {
  description = "Name of the JWT signing key secret"
  value       = aws_secretsmanager_secret.jwt_signing_key.name
}
