# modules/ssm/main.tf

# ---------------------------------------------------------------------------
# 1. ECR REPOSITORY URL PARAMETERS - one per service (auth, book, borrow,
#    frontend, worker). CI/CD and Kubernetes deployment manifests read
#    these instead of having the URL hardcoded anywhere - if you ever
#    rebuild ECR repos, only these parameters need updating, not every
#    manifest file.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "ecr_repository_url" {
  for_each = var.ecr_repository_urls

  name  = "/${var.project_name}/${var.environment}/ecr/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Name    = "${var.project_name}-${var.environment}-ecr-${each.key}"
    Service = each.key
  }
}

# ---------------------------------------------------------------------------
# 2. GENERIC CONFIG PARAMETERS - anything else non-secret (cluster name,
#    RDS endpoint, S3 bucket name, etc.), passed in as a plain map so this
#    module stays flexible without needing a new variable per config item.
#    IMPORTANT: type = "String", NOT "SecureString" - this module is for
#    plain config only. Anything sensitive belongs in modules/secrets/
#    (Secrets Manager), not here.
# ---------------------------------------------------------------------------
resource "aws_ssm_parameter" "config" {
  for_each = var.additional_parameters

  name  = "/${var.project_name}/${var.environment}/config/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Name = "${var.project_name}-${var.environment}-config-${each.key}"
  }
}
