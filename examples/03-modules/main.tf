# 03. 모듈 호출 — 보안 기본값 모듈을 두 번 사용 (로그 버킷 + 데이터 버킷)
#
# 실행하려면 AWS 자격증명이 필요하다:
#   export AWS_PROFILE=study  (또는 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 환경변수)
# 자격증명 없이도 init / validate / fmt 는 가능하다.

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

  # 프로바이더 레벨 기본 태그 — 모든 리소스에 자동 적용
  default_tags {
    tags = {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project" {
  type    = string
  default = "tfstudy"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "name_suffix" {
  description = "버킷 이름 전역 유일성 확보용 (예: 계정ID 뒷자리)"
  type        = string
}

locals {
  prefix = "${var.project}-${var.env}"
}

# 1) 로그 버킷 — 자기 자신을 로깅할 수 없으므로 log_bucket 은 null
module "log_bucket" {
  source = "./modules/s3-secure-bucket"

  bucket_name            = "${local.prefix}-logs-${var.name_suffix}"
  expire_noncurrent_days = 365
  tags                   = { Purpose = "access-logs" }
}

# 2) 데이터 버킷들 — for_each 로 여러 개, 모두 로그 버킷으로 로깅
module "data_bucket" {
  source   = "./modules/s3-secure-bucket"
  for_each = toset(["raw", "processed"])

  bucket_name = "${local.prefix}-${each.key}-${var.name_suffix}"
  log_bucket  = module.log_bucket.id # 암묵적 의존성: 로그 버킷 먼저 생성
  tags        = { Purpose = each.key }
}

output "log_bucket_arn" {
  value = module.log_bucket.arn
}

output "data_bucket_arns" {
  value = { for k, m in module.data_bucket : k => m.arn }
}
