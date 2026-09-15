# 05-a. 일부러 취약하게 만든 코드 — 절대 실제 계정에 apply 하지 말 것
#
# 스캐너를 돌리기 전에 먼저 눈으로 찾아보고 docs/06-security.md 의 카탈로그와 대조한다.
# 찾아야 할 문제: 10개 이상

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" } # [1] 버전 미고정
  }
}

provider "aws" {
  region     = "ap-northeast-2"
  access_key = "AKIAIOSFODNN7EXAMPLE"                     # [2] 하드코딩 자격증명 (AWS 공식 예시 키)
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" # [2]
}

# 공개 버킷
resource "aws_s3_bucket" "public" {
  bucket = "company-backups-public"
}

resource "aws_s3_bucket_acl" "public" {
  bucket = aws_s3_bucket.public.id
  acl    = "public-read" # [3] 퍼블릭 ACL
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket                  = aws_s3_bucket.public.id
  block_public_acls       = false # [4] 퍼블릭 차단 해제
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
# [5] 암호화 / 버전 관리 / 로깅 설정 없음

# 전체 개방 보안그룹
resource "aws_security_group" "wide_open" {
  name        = "wide-open"
  description = "allow everything"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # [6] 모든 포트 전세계 개방
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # [7] SSH 전세계 개방
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 비밀번호 하드코딩 + 암호화 없음 + 공개 DB
resource "aws_db_instance" "db" {
  identifier          = "app-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = "P@ssw0rd123!" # [8] 하드코딩 시크릿
  publicly_accessible = true           # [9] 인터넷 노출
  storage_encrypted   = false          # [10] 저장 암호화 없음
  skip_final_snapshot = true
  deletion_protection = false # [11] 삭제 보호 없음
  # [12] 백업 보존 기간, 감사 로그 없음
}

# 관리자 권한 정책
resource "aws_iam_policy" "admin_all" {
  name = "app-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*" # [13] 전체 권한
      Resource = "*"
    }]
  })
}

# 암호화 안 된 볼륨 + 사용자 데이터에 시크릿
resource "aws_instance" "web" {
  ami           = "ami-0c9c942bd7bf113a2"
  instance_type = "t3.micro"
  vpc_security_group_ids = [aws_security_group.wide_open.id]
  associate_public_ip_address = true

  root_block_device {
    encrypted = false # [14] EBS 암호화 없음
  }

  user_data = <<-EOT
    #!/bin/bash
    export DB_PASSWORD="P@ssw0rd123!"          # [15] user_data 는 메타데이터로 평문 조회 가능
    curl -sSL https://example.com/setup.sh | bash   # [16] 검증 없는 원격 스크립트 실행
  EOT

  metadata_options {
    http_tokens = "optional" # [17] IMDSv1 허용 → SSRF 로 자격증명 탈취 경로
  }
}

output "db_password" {
  value = aws_db_instance.db.password # [18] sensitive 없이 시크릿 출력
}
