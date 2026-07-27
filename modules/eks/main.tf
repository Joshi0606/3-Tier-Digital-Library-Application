# modules/eks/main.tf

# ---------------------------------------------------------------------------
# 1. THE EKS CLUSTER (control plane) - AWS-managed, you don't see the
#    actual VMs running this. This is the "brain" that schedules pods.
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-eks"
  role_arn = var.eks_cluster_role_arn          # <-- from modules/iam/
  version  = var.cluster_version

  vpc_config {
    # Control plane ENIs get placed across BOTH public and private subnets
    # for redundancy/reachability - this is different from where your
    # worker NODES live (private only, set in the node group below).
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)

    # true = you (and CI/CD) can reach the Kubernetes API from the internet
    # (needed for kubectl/GitHub Actions to deploy). In a stricter setup
    # you'd set this false and use a VPN/bastion instead.
    endpoint_public_access  = true
    endpoint_private_access = true
    # For production hardening: restrict public_access_cidrs to your office/VPN IP
    # public_access_cidrs = ["YOUR_IP/32"]
  }

  # API mode enables EKS Access Entries (the modern, Terraform-native way to
  # grant IAM principals access to the cluster) instead of the legacy
  # aws-auth ConfigMap. API_AND_CONFIG_MAP keeps backward compatibility
  # if any existing aws-auth entries exist.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks"
  }
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprint_list
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-oidc"
  }
}

# ---------------------------------------------------------------------------
# 2. LAUNCH TEMPLATE - the only way to attach OUR custom security group (the
#    one built in modules/vpc/ with the ALB->node ingress rules) to the
#    actual EC2 instances. Without this, AWS silently creates its own
#    default SG for the node group, and our whole SG chain (ALB -> Node ->
#    RDS) never actually applies to real traffic.
#
#    We deliberately do NOT set image_id or instance_type here - the node
#    group manages those itself (keeps AMI updates automatic). We ONLY
#    override the security group.
# ---------------------------------------------------------------------------
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"

  # Attach BOTH our custom SG AND the EKS cluster SG.
  # The cluster SG (auto-created by AWS) carries the control-plane <-> node
  # rules that kubelet needs to register. Without it, nodes boot but never
  # join the cluster. Our custom SG adds the ALB->pod and node-to-node rules.
  vpc_security_group_ids = [
    var.eks_nodes_security_group_id,
    aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  ]

  # Required so the node can call AWS APIs (ECR, EC2, EKS) before the
  # kubelet fully starts. Without this, the node fails to bootstrap.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2 - more secure
    http_put_response_hop_limit = 2            # needs to be 2 for containers to reach IMDS
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-nodes-lt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# 3. NODE GROUP - the actual EC2 worker nodes. References the launch
#    template above to get our custom SG applied.
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-node-group"
  node_role_arn   = var.eks_node_role_arn
  subnet_ids      = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  instance_types = var.node_instance_types

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-node-group"
  }

  depends_on = [aws_eks_cluster.main]
}

# ---------------------------------------------------------------------------
# 4. CI/CD ACCESS ENTRY - grants the GitHub Actions IAM user (or role)
#    cluster-admin rights so kubectl can apply manifests.
#
#    This replaces the legacy aws-auth ConfigMap approach. EKS Access Entries
#    are managed entirely via the AWS API — no in-cluster ConfigMap edits.
# ---------------------------------------------------------------------------
resource "aws_eks_access_entry" "ci_cd" {
  count         = var.ci_cd_principal_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.ci_cd_principal_arn

  # STANDARD type = regular IAM user or role (not a node/Fargate profile)
  type = "STANDARD"

  tags = {
    Name = "${var.project_name}-${var.environment}-cicd-access-entry"
  }
}

resource "aws_eks_access_policy_association" "ci_cd_admin" {
  count         = var.ci_cd_principal_arn != "" ? 1 : 0

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.ci_cd_principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ci_cd]
}
