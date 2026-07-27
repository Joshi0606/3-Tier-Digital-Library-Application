output "sonarqube_public_ip" {
  description = "Public IP address of SonarQube EC2 instance"
  value       = aws_instance.sonarqube.public_ip
}

output "sonarqube_public_dns" {
  description = "Public DNS of SonarQube EC2 instance"
  value       = aws_instance.sonarqube.public_dns
}

output "sonarqube_url" {
  description = "URL to access SonarQube"
  value       = "http://${aws_instance.sonarqube.public_ip}:9000"
}

output "sonarqube_security_group_id" {
  description = "Security group ID for SonarQube"
  value       = aws_security_group.sonarqube.id
}

output "sonarqube_instance_id" {
  description = "EC2 instance ID of SonarQube"
  value       = aws_instance.sonarqube.id
}
