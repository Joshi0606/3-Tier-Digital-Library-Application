# get 5 repos (auth, book, borrow, frontend, worker) from a single block
# instead of writing aws_ecr_repository 5 separate times.
resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name = "${var.project_name}-${each.value}"

  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  # Tags every repo with project/environment/service name, so it's clear
  # in the AWS console which service each repo belongs to.
  tags = {
    Name        = "${var.project_name}-${each.value}"
    Environment = var.environment
    Service     = each.value
  }
}

# Lifecycle policy: automatically clean up old, untagged images so the
# repo doesn't accumulate unlimited storage cost from every CI build.
# Without this, every "docker push" from CI/CD leaves an orphaned image
# behind forever once it's replaced by a newer tag.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
