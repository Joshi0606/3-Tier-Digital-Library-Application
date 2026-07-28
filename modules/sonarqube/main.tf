# Security Group for SonarQube
resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Security group for SonarQube"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-sonarqube-sg"
  }
}

# Ingress: Allow HTTP from anywhere (for CI/CD)
resource "aws_security_group_rule" "sonarqube_http" {
  type              = "ingress"
  from_port         = 9000
  to_port           = 9000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sonarqube.id
}

# Ingress: Allow SSH for management
resource "aws_security_group_rule" "sonarqube_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_allowed_cidr
  security_group_id = aws_security_group.sonarqube.id
}

# Egress: Allow all outbound traffic
resource "aws_security_group_rule" "sonarqube_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sonarqube.id
}

# EC2 Instance for SonarQube
resource "aws_instance" "sonarqube" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.sonarqube.id]
  key_name               = var.key_name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    sonarqube_version = var.sonarqube_version
  }))

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-sonarqube"
  }

  lifecycle {
    prevent_destroy = true   # prevents terraform apply from destroying this instance
    ignore_changes  = [ami, user_data]
  }

  depends_on = [aws_security_group.sonarqube]
}

# Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
