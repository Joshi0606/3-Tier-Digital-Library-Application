output "vpc_id" {
  description = "The VPC ID - almost every other module needs this"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Subnet IDs for the ALB"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Subnet IDs for EKS worker nodes AND RDS (shared tier)"
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "SG ID to attach to the ALB"
  value       = aws_security_group.alb.id
}

output "eks_nodes_security_group_id" {
  description = "SG ID to attach to EKS worker nodes"
  value       = aws_security_group.eks_nodes.id
}

output "rds_security_group_id" {
  description = "SG ID to attach to RDS"
  value       = aws_security_group.rds.id
}
