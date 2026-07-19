# modules/ssm/outputs.tf

# Map of service name -> SSM parameter name (not the value itself) for
# ECR URLs. CI/CD workflows use this parameter NAME to fetch the value
# at deploy time via `aws ssm get-parameter`.
output "ecr_parameter_names" {
  description = "Map of service name to SSM parameter name for ECR repo URLs"
  value = {
    for name, param in aws_ssm_parameter.ecr_repository_url : name => param.name
  }
}

# Map of config key -> SSM parameter name for the generic config values.
output "config_parameter_names" {
  description = "Map of config key to SSM parameter name for generic config values"
  value = {
    for name, param in aws_ssm_parameter.config : name => param.name
  }
}
