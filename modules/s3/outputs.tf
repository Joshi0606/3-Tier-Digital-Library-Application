output "bucket_name" {
  description = "Name of the assets S3 bucket"
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "ARN of the assets S3 bucket"
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the assets S3 bucket"
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
