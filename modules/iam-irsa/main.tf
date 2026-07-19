# modules/iam-irsa/main.tf

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# 1. APP POD IRSA ROLE - trusts ONLY the app's specific service account,
#    same pattern as modules/alb-controller/. This is what lets your
#    auth/book/borrow/frontend/worker pods call AWS APIs (S3, SQS, Secrets
#    Manager) WITHOUT AWS access keys baked into a Docker image or env var.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "app_pod" {
  name = "${var.project_name}-${var.environment}-app-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-app-pod-role"
  }
}

# ---------------------------------------------------------------------------
# 2. APP PERMISSIONS POLICY - scoped to EXACTLY the resources this app
#    needs, and nothing else. Each Resource line points at a specific ARN
#    passed in from another module's outputs - never "*". This is the
#    least-privilege principle: if this role's credentials ever leaked,
#    the blast radius is "one S3 bucket, two SQS queues, one secret" -
#    not the whole AWS account.
# ---------------------------------------------------------------------------
resource "aws_iam_policy" "app_pod" {
  name = "${var.project_name}-${var.environment}-app-pod-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3AssetsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${var.assets_bucket_arn}/*"
      },
      {
        Sid    = "SQSOrdersAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          var.orders_queue_arn,
          var.orders_dlq_arn
        ]
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          var.jwt_signing_key_secret_arn,
          var.rds_master_user_secret_arn
        ]
      },
      {
        Sid    = "SSMConfigAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        # Scoped to this project/environment path only — not all SSM params in the account
        Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_pod" {
  role       = aws_iam_role.app_pod.name
  policy_arn = aws_iam_policy.app_pod.arn
}

# ---------------------------------------------------------------------------
# 3. CLOUDWATCH AGENT IRSA ROLE - separate role, separate trust condition,
#    for the CloudWatch agent pod (ships container logs/metrics to the
#    log groups built in modules/cloudwatch/). Kept SEPARATE from the app
#    pod role on purpose: the agent needs write access to CloudWatch Logs,
#    the app needs S3/SQS/Secrets access - no reason for either identity
#    to hold permissions it doesn't use.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.project_name}-${var.environment}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.cloudwatch_agent_namespace}:${var.cloudwatch_agent_service_account_name}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudwatch-agent-role"
  }
}

# AWS-managed policy for the CloudWatch agent - standard permissions to
# write log streams/events and put custom metrics. No need to hand-write
# this one; it's a well-known AWS-maintained policy for exactly this purpose.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
