# 보안 기본값이 굳어진 S3 버킷 모듈
#
# 호출자가 아무 옵션도 안 줘도 다음이 보장된다:
#   - 퍼블릭 접근 4중 차단
#   - 저장 시 암호화 (SSE-S3 또는 SSE-KMS)
#   - 버전 관리 (기본 on)
#   - TLS 아닌 요청 거부 (버킷 정책)
#   - 소유권 강제 (ACL 비활성)
#   - 이전 버전 수명주기 정리
#   - 선택: 액세스 로깅

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

# 1) 퍼블릭 접근 차단 — 4개 모두 true 가 아니면 tfsec/checkov 가 잡는다
resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2) ACL 비활성 (BucketOwnerEnforced) — 객체 ACL 로 뚫리는 경로 제거
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 3) 저장 시 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

# 4) 버전 관리
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

# 5) 이전 버전 정리
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket     = aws_s3_bucket.this.id
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.expire_noncurrent_days
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# 6) TLS 강제 정책 — 평문 HTTP 요청 거부
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket     = aws_s3_bucket.this.id
  policy     = data.aws_iam_policy_document.tls_only.json
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# 7) 액세스 로깅 (선택)
resource "aws_s3_bucket_logging" "this" {
  count = var.log_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket
  target_prefix = "s3-access/${var.bucket_name}/"
}
