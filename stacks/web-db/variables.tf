variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project" {
  description = "리소스 이름 접두어로 쓰이는 프로젝트 식별자"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project 는 소문자로 시작하는 3~21자 [a-z0-9-] 여야 합니다."
  }
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment 는 dev / stage / prod 중 하나여야 합니다."
  }
}

variable "account_suffix" {
  description = "S3 버킷 전역 유일성을 위한 접미어 (예: 계정 ID 뒷 4자리)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "웹 인스턴스와 DB 를 둘 프라이빗 서브넷. 최소 2개(AZ 분산)"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "가용영역 분산을 위해 프라이빗 서브넷을 2개 이상 지정해야 합니다."
  }
}

variable "admin_cidrs" {
  description = "SSH(22) 접근을 허용할 관리 CIDR. 전체 개방은 validation 으로 거부"
  type        = list(string)

  validation {
    condition = (
      length(var.admin_cidrs) > 0 &&
      !contains(var.admin_cidrs, "0.0.0.0/0") &&
      alltrue([for c in var.admin_cidrs : can(cidrnetmask(c))])
    )
    error_message = "admin_cidrs 는 1개 이상의 유효한 IPv4 CIDR 이어야 하며 0.0.0.0/0 을 포함할 수 없습니다."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_multi_az" {
  description = "RDS 다중 AZ. prod 는 true 를 precondition 으로 강제"
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 7

  validation {
    condition     = var.db_backup_retention_days >= 7
    error_message = "백업 보존 기간은 7일 이상이어야 합니다."
  }
}
