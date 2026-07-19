# each service (e.g. "123456789012.dkr.ecr.us-east-1.amazonaws.com/digital-library-auth").
output "repository_urls" {
  description = "Map of service name to ECR repository URL"
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.repository_url
  }
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN"
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.arn
  }
}

output "repository_names" {
  description = "Map of service name to ECR repository name"
  value = {
    for name, repo in aws_ecr_repository.this : name => repo.name
  }
}
