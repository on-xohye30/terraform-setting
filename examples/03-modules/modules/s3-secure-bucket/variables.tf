variable "bucket_name" {
  description = "버킷 이름 (전역 유일)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "S3 버킷 이름 규칙(소문자/숫자/./-, 3~63자)을 지켜야 합니다."
  }
}

variable "versioning" {
  description = "버전 관리 활성화 (기본 on — 실수 삭제/랜섬웨어 복구용)"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "SSE-KMS 키 ARN. null 이면 SSE-S3(AES256) 사용"
  type        = string
  default     = null
}

variable "log_bucket" {
  description = "액세스 로그를 보낼 버킷 이름. null 이면 로깅 비활성 (로그 버킷 자신일 때)"
  type        = string
  default     = null
}

variable "expire_noncurrent_days" {
  description = "이전 버전 객체 만료 일수"
  type        = number
  default     = 90
}

variable "force_destroy" {
  description = "destroy 시 객체가 있어도 삭제. prod 는 false 유지"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
