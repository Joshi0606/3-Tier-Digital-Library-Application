data "aws_caller_identity" "current" {}

# IAM Role — App Pods (IRSA)

resource "aws_iam_role" "app_pod" {
  name = "${var.project_name}-${var.environment}-app-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.app_namespace}:${var.app_service_account_name}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-app-pod-role" }
}

resource "aws_iam_policy" "app_pod" {
  name = "${var.project_name}-${var.environment}-app-pod-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3AssetsAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.assets_bucket_arn}/*"
      },
      {
        Sid    = "SQSOrdersAccess"
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [var.orders_queue_arn, var.orders_dlq_arn]
      },
      {
        Sid      = "SecretsManagerAccess"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.jwt_signing_key_secret_arn, var.rds_master_user_secret_arn]
      },
      {
        Sid    = "SSMConfigAccess"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/*"
      },
      {
        Sid      = "SNSPublishAccess"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${var.project_name}-${var.environment}-alerts"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_pod" {
  role       = aws_iam_role.app_pod.name
  policy_arn = aws_iam_policy.app_pod.arn
}

# IAM Role — CloudWatch Agent (IRSA)

resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.project_name}-${var.environment}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.cloudwatch_agent_namespace}:${var.cloudwatch_agent_service_account_name}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = { Name = "${var.project_name}-${var.environment}-cloudwatch-agent-role" }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
