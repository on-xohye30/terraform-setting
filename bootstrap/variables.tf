variable "region" {
  description = "state 저장소를 둘 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "Terraform state 버킷 이름 (전역 유일). 예: myorg-tfstate-prod-1234"
  type        = string

  validation {
    condition     = can(regex("tfstate", var.state_bucket_name))
    error_message = "state 버킷임을 이름에서 알 수 있도록 'tfstate' 를 포함해야 합니다."
  }
}

variable "lock_table_name" {
  description = "state 잠금용 DynamoDB 테이블 이름"
  type        = string
  default     = "terraform-locks"
}

variable "noncurrent_state_retention_days" {
  description = "이전 state 버전 보관 일수. 사고 조사·롤백 여유를 위해 충분히 길게 둔다"
  type        = number
  default     = 365
}
