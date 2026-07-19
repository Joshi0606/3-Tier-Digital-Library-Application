
# 1. DB SUBNET GROUP - tells RDS which subnets it's allowed to use.
#    RDS won't accept raw subnet_ids directly on the instance - it needs
#    this wrapper resource, mainly because Multi-AZ deployments need RDS
#    to know about MULTIPLE subnets across different AZs.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# 2. THE RDS INSTANCE ITSELF
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-${var.environment}-db"
  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type       = "gp3"
  storage_encrypted  = true   # encrypts data at rest - free, no reason not to

  db_name  = var.db_name
  username = var.db_username
  # NO password attribute - manage_master_user_password below handles this.
  # AWS creates and OWNS its own Secrets Manager secret with the master
  # password, and rotates it automatically. The password never touches
  # Terraform state or our source code at all.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]   # from modules/vpc/ - only trusts EKS node SG on port 3306

  multi_az = var.db_multi_az  

  skip_final_snapshot = true

  backup_retention_period = 0  # free tier does not support automated backups

  tags = {
    Name = "${var.project_name}-${var.environment}-db"
  }
}
