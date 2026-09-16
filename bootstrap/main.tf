# 원격 state 저장소 부트스트랩
#
# state 파일은 리소스의 모든 속성(비밀번호·키 포함)을 평문으로 담는다.
# 따라서 state 버킷은 이 저장소에서 가장 엄격하게 보호되는 리소스다.

module "state_bucket" {
  source = "../modules/s3-secure-bucket"

  bucket_name            = var.state_bucket_name
  versioning             = true # state 손상·오염 시 이전 버전으로 복구
  expire_noncurrent_days = var.noncurrent_state_retention_days
  force_destroy          = false
  tags                   = { Purpose = "terraform-state" }
}

# state 잠금 테이블.
# Terraform 1.10+ 는 backend "s3" 의 use_lockfile 로 DynamoDB 없이 잠금이 가능하지만,
# 1.6~1.9 사용자와의 호환을 위해 테이블을 유지한다.
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

  deletion_protection_enabled = true

  lifecycle {
    prevent_destroy = true
  }

  tags = { Purpose = "terraform-state-lock" }
}

# state 버킷에 대한 최소권한 정책 문서.
# CI 역할이나 운영자 그룹에 붙여 "state 를 읽고 쓸 수 있는 주체" 를 명시적으로 제한한다.
#tfsec:ignore:aws-iam-no-policy-wildcards 객체 키는 스택마다 달라 "<state-bucket>/*" 가 최소 범위. 버킷 자체는 단일 ARN 으로 고정
data "aws_iam_policy_document" "state_access" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.state_bucket.arn]
  }

  statement {
    sid       = "ReadWriteStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${module.state_bucket.arn}/*"]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.locks.arn]
  }
}

resource "aws_iam_policy" "state_access" {
  name        = "${var.state_bucket_name}-access"
  description = "Terraform remote state read/write + lock"
  policy      = data.aws_iam_policy_document.state_access.json
}
