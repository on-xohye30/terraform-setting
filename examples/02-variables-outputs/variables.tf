variable "project" {
  description = "프로젝트 이름 (리소스 이름 접두어)"
  type        = string
  default     = "tfstudy"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project))
    error_message = "project 는 소문자로 시작하는 3~21자 [a-z0-9-] 여야 합니다."
  }
}

variable "env" {
  description = "배포 환경"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env 는 dev / stage / prod 중 하나여야 합니다."
  }
}

variable "allowed_cidrs" {
  description = "관리 접근을 허용할 CIDR 목록"
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "allowed_cidrs 의 모든 항목은 유효한 IPv4 CIDR 이어야 합니다."
  }

  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 (전체 개방) 은 허용하지 않습니다."
  }
}

variable "servers" {
  description = "서버 정의. 키가 서버 이름이 된다 (for_each 용)"
  type = map(object({
    port    = number
    size    = optional(string, "small")
    public  = optional(bool, false)
    monitor = optional(bool, true)
  }))
  default = {
    web = { port = 443, public = true }
    api = { port = 8080 }
    db  = { port = 5432, size = "large", monitor = true }
  }

  validation {
    condition     = alltrue([for s in values(var.servers) : s.port > 0 && s.port < 65536])
    error_message = "port 는 1~65535 범위여야 합니다."
  }
}

variable "extra_tags" {
  description = "추가 태그"
  type        = map(string)
  default     = {}
}

variable "db_password" {
  description = "DB 비밀번호. 빈 값이면 랜덤 생성. 실제로는 TF_VAR_db_password 환경변수로 주입할 것"
  type        = string
  default     = ""
  sensitive   = true
}
