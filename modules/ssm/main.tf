# SSM Parameters — ECR URLs

resource "aws_ssm_parameter" "ecr_repository_url" {
  for_each = var.ecr_repository_urls
  name     = "/${var.project_name}/${var.environment}/ecr/${each.key}"
  type     = "String"
  value    = each.value

  tags = {
    Name    = "${var.project_name}-${var.environment}-ecr-${each.key}"
    Service = each.key
  }
}

# SSM Parameters — App Config

resource "aws_ssm_parameter" "config" {
  for_each = var.additional_parameters
  name     = "/${var.project_name}/${var.environment}/config/${each.key}"
  type     = "String"
  value    = each.value

  tags = {
    Name = "${var.project_name}-${var.environment}-config-${each.key}"
  }
}
