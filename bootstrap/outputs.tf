output "state_bucket" {
  description = "state 버킷 이름"
  value       = module.state_bucket.id
}

output "lock_table" {
  description = "잠금 테이블 이름"
  value       = aws_dynamodb_table.locks.name
}

output "state_access_policy_arn" {
  description = "CI 역할/운영자에게 부여할 state 접근 정책 ARN"
  value       = aws_iam_policy.state_access.arn
}

output "backend_config" {
  description = "스택의 backend.hcl 로 그대로 저장할 내용 (terraform output -raw backend_config)"
  value       = <<-EOT
    bucket         = "${module.state_bucket.id}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
    encrypt        = true
  EOT
}
