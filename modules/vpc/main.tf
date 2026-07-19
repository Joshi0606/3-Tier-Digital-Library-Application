resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # lets resources inside resolve AWS DNS names
  enable_dns_hostnames = true # required for EKS and RDS to work properly

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true # needed so the ALB gets a public IP

  tags = {
    Name                     = "${var.project_name}-${var.environment}-public-${count.index}"
    "kubernetes.io/role/elb" = "1" # tells AWS LB Controller "a public ALB may live here"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.11.0/24
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                              = "${var.project_name}-${var.environment}-private-${count.index}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}


resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip-${count.index}"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-${count.index}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index % var.nat_gateway_count].id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# 5. SECURITY GROUPS
#   Internet -> [ALB SG: port 80 from anywhere]
#            -> [EKS Node SG: app ports 80/5001/5002/5003, ONLY from ALB SG]
#            -> [RDS SG: port 3306, ONLY from Node SG]
# --- SG 1: ALB - public facing ---
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-"
  description = "Allows inbound web traffic from the internet to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere on the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow ALB to forward traffic anywhere (needs to reach the nodes)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- SG 2: EKS worker nodes - where your pods run ---
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"
  description = "Allows traffic from the ALB into pods, and node-to-node traffic for the EKS cluster itself"
  vpc_id      = aws_vpc.main.id

  # ALB -> pods, directly on each app's real port. This works because the
  # AWS Load Balancer Controller runs in "ip" target mode (talks straight
  # to pod IPs), not the 30000-32767 NodePort range.
  dynamic "ingress" {
    for_each = var.alb_target_ports
    content {
      description     = "Traffic from the ALB to pods on app port ${ingress.value}"
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb.id]
    }
  }

  # ALB Controller webhook - the controller runs as a pod and AWS calls
  # back to it on 443 to validate/mutate Ingress resources. Without this
  # the ALB controller pod will fail with webhook timeout errors.
  ingress {
    description     = "ALB Controller webhook from ALB SG"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Nodes need to talk to each other (kubelet, DNS, cluster networking).
  ingress {
    description = "Node to node communication (required by EKS/kubelet)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow nodes to reach anything (Docker pulls, AWS APIs, RDS, etc)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-nodes-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- SG 3: RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-"
  description = "Allows MySQL traffic only from EKS worker nodes - nothing else, not even the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from EKS pods only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    description = "RDS rarely needs to initiate outbound, but AWS requires an egress rule"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}
