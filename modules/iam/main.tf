# EKS CLUSTER ROLE 
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  # Trust policy: ONLY the eks.amazonaws.com AWS service is allowed to
  # assume (wear) this role. Nothing else - not an EC2 instance, not a
  # user - can use these permissions.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# 2. EKS NODE ROLE
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-${var.environment}-eks-node-role"

  # Trust policy: only EC2 instances can assume this role (worker nodes
  # ARE EC2 instances under the hood).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# 3 AWS-managed policies a worker node needs, attached separately:

# Lets the node register itself with the EKS cluster and receive
# instructions from the control plane (kubelet talking to the API server).
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Lets the node manage networking for pods (VPC CNI plugin assigns each
# pod a real VPC IP - this is what makes "ip mode" ALB targeting possible).
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Lets the node PULL container images from ECR (your auth/book/borrow/
# frontend images) - without this, pods would fail to start with an
# image pull error.
resource "aws_iam_role_policy_attachment" "eks_ecr_readonly_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
