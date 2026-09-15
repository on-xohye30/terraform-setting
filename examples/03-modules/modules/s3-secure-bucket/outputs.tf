output "id" {
  description = "버킷 이름(ID)"
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "버킷 ARN"
  value       = aws_s3_bucket.this.arn
}

output "domain_name" {
  description = "버킷 도메인"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
