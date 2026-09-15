# 04-a. 원격 상태 백엔드 부트스트랩
#
# "state 를 저장할 버킷"은 그 자체가 Terraform 으로 관리되지만, 아직 원격 백엔드가 없으므로
# 이 디렉터리만은 로컬 state 로 1회 apply 한다 (닭과 달걀 문제).
# 이후 이 디렉터리의 terraform.tfstate 는 안전한 곳에 보관하거나, 생성된 버킷으로 migrate 한다.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_bucket_name" {
  description = "state 버킷 이름 (전역 유일)"
  type        = string
}

variable "lock_table_name" {
  type    = string
  default = "terraform-locks"
}

# 03 에서 만든 보안 기본값 모듈을 재사용
module "state_bucket" {
  source = "../../03-modules/modules/s3-secure-bucket"

  bucket_name            = var.state_bucket_name
  versioning             = true # state 손상 시 이전 버전으로 복구
  expire_noncurrent_days = 180
  force_destroy          = false
  tags                   = { Purpose = "terraform-state" }
}

# state 버킷 삭제 보호(prevent_destroy)는 모듈 밖에서 걸 수 없으므로,
# 실무에서는 모듈 내부 lifecycle 로 두거나 state 전용 모듈을 따로 만든다.

# 잠금 테이블 (Terraform 1.10+ 는 backend "s3" 의 use_lockfile = true 로 대체 가능)
resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = { Purpose = "terraform-state-lock" }
}

output "backend_config" {
  description = "다른 프로젝트의 backend.hcl 에 그대로 붙여넣을 값"
  value       = <<-EOT
    bucket         = "${module.state_bucket.id}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
    encrypt        = true
  EOT
}
