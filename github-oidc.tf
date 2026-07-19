# github-oidc.tf
# Creates the AWS OIDC provider and IAM roles that allow GitHub Actions
# to authenticate to AWS without any stored access keys.
#
# How it works:
#   1. GitHub generates a signed JWT token for each workflow run
#   2. AWS verifies the token against the GitHub OIDC provider
#   3. AWS issues temporary credentials scoped to the role below
#   4. Credentials expire when the job ends — nothing to rotate or leak
#
# After applying, set these in GitHub repo Settings → Secrets:
#   (nothing — no secrets needed, that's the point)
#
# Set this in GitHub repo Settings → Variables (not secrets):
#   AWS_ROLE_ARN_INFRA → output: github_actions_infra_role_arn
#   AWS_ROLE_ARN_CICD  → output: github_actions_cicd_role_arn

# ── GitHub OIDC Provider ─────────────────────────────────────
# Registered once per AWS account. If you already have one, import it:
#   terraform import aws_iam_openid_connect_provider.github \
#     arn:aws:iam::393323650493:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # GitHub's OIDC thumbprint — stable, published by GitHub
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1",
                     "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = {
    Name = "github-actions-oidc"
  }
}

# ── Local: your GitHub repo in owner/repo format ─────────────
locals {
  github_repo = var.github_repo  # set in terraform.tfvars
}

# ── Role 1: Infrastructure pipeline ─────────────────────────
# Used by infrastructure.yml — needs full Terraform permissions
# (create/modify/destroy all resources in this project).
resource "aws_iam_role" "github_actions_infra" {
  name = "${var.project_name}-${var.environment}-github-infra-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Only the main branch can assume this role
          # ref:refs/heads/main = push to main
          # pull_request events use refs/pull/*/merge
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-github-infra-role"
  }
}

# Terraform needs broad permissions to manage all the infrastructure
# resources in this project. Scoped to this account only.
resource "aws_iam_role_policy" "github_actions_infra" {
  name = "terraform-permissions"
  role = aws_iam_role.github_actions_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::ak2.kops",
          "arn:aws:s3:::ak2.kops/*"
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::ak2.kops/digital-library/prod/terraform.tfstate.tflock"
      },
      {
        Sid    = "ManageInfrastructure"
        Effect = "Allow"
        Action = [
          "ec2:*", "eks:*", "iam:*", "rds:*",
          "s3:*", "sqs:*", "sns:*", "ssm:*",
          "secretsmanager:*", "ecr:*", "logs:*",
          "cloudwatch:*", "elasticloadbalancing:*",
          "autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "EKSHelm"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Role 2: CI/CD pipeline ───────────────────────────────────
# Used by ci-cd.yml — needs ECR push + EKS deploy only.
# Much narrower than the infra role.
resource "aws_iam_role" "github_actions_cicd" {
  name = "${var.project_name}-${var.environment}-github-cicd-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Allow both main branch pushes AND pull request checks
          "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:*"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-github-cicd-role"
  }
}

resource "aws_iam_role_policy" "github_actions_cicd" {
  name = "cicd-permissions"
  role = aws_iam_role.github_actions_cicd.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        # Scoped to only this project's ECR repos
        Resource = "arn:aws:ecr:us-east-1:393323650493:repository/digital-library-*"
      },
      {
        Sid    = "EKSDeploy"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSNotify"
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = "arn:aws:sns:us-east-1:393323650493:digital-library-prod-alerts"
      }
    ]
  })
}

# ── Outputs ──────────────────────────────────────────────────
output "github_actions_infra_role_arn" {
  description = "Set as AWS_ROLE_ARN in GitHub repo variables for infrastructure.yml"
  value       = aws_iam_role.github_actions_infra.arn
}

output "github_actions_cicd_role_arn" {
  description = "Set as AWS_ROLE_ARN_CICD in GitHub repo variables for ci-cd.yml"
  value       = aws_iam_role.github_actions_cicd.arn
}
