# modules/alb-controller/main.tf

# 1. IRSA ROLE - trusts ONE SPECIFIC Kubernetes service account, not the
#    whole EC2 instance. This is the key difference from modules/iam/'s
#    node role: that role is worn by every pod on the node (too broad
#    for this). This role can ONLY be assumed by the exact service
#    account "aws-load-balancer-controller" in namespace "kube-system" -
#    nothing else on the cluster can use these permissions.

resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-${var.environment}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      # Principal: trust identity tokens signed by THIS cluster's OIDC
      # provider (from modules/eks/), not just any AWS service.
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      # Condition: even within this cluster's OIDC provider, ONLY trust
      # tokens claiming to be this exact service account. This is what
      # "scopes" the role to one specific Kubernetes identity, not
      # every pod in the cluster.
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-controller-role"
  }
}

# 2. PERMISSIONS POLICY - what the controller can actually DO once it
#    has assumed the role above. AWS publishes and maintains this policy
#    officially (it changes as the controller adds features), so we
#    fetch it fresh rather than hand-copying it into our own Terraform,
#    which would go stale.

data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.project_name}-${var.environment}-alb-controller-policy"
  policy = data.http.alb_controller_policy.response_body
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
