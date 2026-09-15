# 05-b. 같은 구성을 안전하게 고친 버전
#
# insecure/main.tf 와 나란히 놓고 diff 로 비교한다.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }   # 버전 고정
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.region
  # 자격증명은 환경변수 / 프로파일 / CI OIDC 로. 코드에 두지 않는다.
}

variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "admin_cidrs" {
  description = "SSH/관리 접근 허용 CIDR"
  type        = list(string)
  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs 는 비어 있을 수 없고 0.0.0.0/0 을 포함할 수 없습니다."
  }
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "name_suffix" {
  type = string
}

# --- S3: 보안 기본값 모듈 재사용 -------------------------------------------
module "backups" {
  source      = "../../03-modules/modules/s3-secure-bucket"
  bucket_name = "company-backups-${var.name_suffix}"
  tags        = { Purpose = "backups" }
}

# --- 보안그룹: 최소 개방 ------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "web-${var.name_suffix}"
  description = "HTTPS from anywhere, SSH from admin CIDRs only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0" # 공개 서비스 포트만 의도적으로 개방
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.web.id
  description       = "SSH from admin"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "db" {
  name        = "db-${var.name_suffix}"
  description = "Postgres from web tier only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "postgres from web sg"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.web.id # CIDR 대신 SG 참조
}

# --- DB: 랜덤 비밀번호 → Secrets Manager, 비공개, 암호화, 보호 ---------------
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "app/db/master-${var.name_suffix}"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "db" {
  name       = "db-${var.name_suffix}"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "db" {
  identifier             = "app-db-${var.name_suffix}"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  username               = "appadmin"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible                 = false
  storage_encrypted                   = true
  deletion_protection                 = true
  backup_retention_period             = 7
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "app-db-${var.name_suffix}-final"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password] # 회전은 Secrets Manager 로 관리
  }
}

# --- IAM: 최소권한 --------------------------------------------------------------
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadOwnSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
  statement {
    sid       = "WriteBackups"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [module.backups.arn, "${module.backups.arn}/*"]
  }
}

resource "aws_iam_policy" "app" {
  name   = "app-policy-${var.name_suffix}"
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_role" "web" {
  name = "web-${var.name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "web" {
  role       = aws_iam_role.web.name
  policy_arn = aws_iam_policy.app.arn
}

resource "aws_iam_instance_profile" "web" {
  name = "web-${var.name_suffix}"
  role = aws_iam_role.web.name
}

# --- EC2: 암호화, IMDSv2, 시크릿은 런타임에 조회 ------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.web.name
  associate_public_ip_address = false # ALB 뒤에 배치
  monitoring                  = true
  ebs_optimized               = true

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 강제
    http_put_response_hop_limit = 1
  }

  # 시크릿은 user_data 에 넣지 않고 인스턴스 역할로 런타임 조회
  user_data = <<-EOT
    #!/bin/bash
    set -euo pipefail
    SECRET_ARN="${aws_secretsmanager_secret.db.arn}"
    echo "DB secret arn: $SECRET_ARN (fetch at runtime via aws secretsmanager get-secret-value)"
  EOT
  user_data_replace_on_change = true
}

output "db_secret_arn" {
  description = "앱이 런타임에 조회할 시크릿 ARN (값이 아니라 위치)"
  value       = aws_secretsmanager_secret.db.arn
}

output "backup_bucket" {
  value = module.backups.id
}
