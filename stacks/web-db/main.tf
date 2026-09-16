locals {
  name = "${var.project}-${var.environment}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 스토리지: 백업 버킷은 보안 기본값 모듈로만 생성한다
# ─────────────────────────────────────────────────────────────────────────────
module "backups" {
  source = "../../modules/s3-secure-bucket"

  bucket_name = "${local.name}-backups-${var.account_suffix}"
  tags        = { Purpose = "backups" }
}

# ─────────────────────────────────────────────────────────────────────────────
# 네트워크 접근 제어: CIDR 이 아니라 보안그룹 간 관계로 정의한다
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "HTTPS from anywhere, SSH from admin CIDRs only"
  vpc_id      = var.vpc_id
}

#tfsec:ignore:aws-ec2-no-public-ingress-sgr 공개 서비스 포트(443)는 의도된 개방
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "SSH from admin CIDR"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr 아웃바운드 제한은 VPC 엔드포인트 도입과 함께 (로드맵)
resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "Postgres from web tier only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_web" {
  security_group_id            = aws_security_group.db.id
  description                  = "postgres from web security group"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.web.id
}

# ─────────────────────────────────────────────────────────────────────────────
# 시크릿: 생성 → Secrets Manager 보관 → 인스턴스는 역할로 런타임 조회
# ─────────────────────────────────────────────────────────────────────────────
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/db/master"
  description             = "RDS master credential for ${local.name}"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "appadmin"
    password = random_password.db.result
    host     = aws_db_instance.db.address
    port     = aws_db_instance.db.port
    dbname   = aws_db_instance.db.db_name
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# 데이터베이스: 비공개, 암호화, 삭제 보호, 감사 로그
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "db" {
  name       = "${local.name}-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "db" {
  identifier     = "${local.name}-db"
  engine         = "postgres"
  instance_class = var.db_instance_class
  db_name        = "app"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_encrypted     = true

  username = "appadmin"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period             = var.db_backup_retention_days
  deletion_protection                 = true
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true
  performance_insights_enabled        = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-db-final"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [password] # 회전은 Secrets Manager 측에서 관리

    precondition {
      condition     = var.environment != "prod" || var.db_multi_az
      error_message = "prod 환경의 RDS 는 multi_az = true 여야 합니다."
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM: 인스턴스가 필요한 것만, 필요한 리소스에만
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "web_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

#tfsec:ignore:aws-iam-no-policy-wildcards 백업 객체 키는 런타임에 생성되므로 "<backups-bucket>/*" 가 최소 범위. 버킷은 단일 ARN
data "aws_iam_policy_document" "web" {
  statement {
    sid       = "ReadOwnDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }

  statement {
    sid       = "ListBackupBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.backups.arn]
  }

  statement {
    sid       = "ReadWriteBackupObjects"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${module.backups.arn}/*"]
  }
}

resource "aws_iam_role" "web" {
  name               = "${local.name}-web"
  assume_role_policy = data.aws_iam_policy_document.web_assume.json
}

resource "aws_iam_role_policy" "web" {
  name   = "${local.name}-web"
  role   = aws_iam_role.web.id
  policy = data.aws_iam_policy_document.web.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  # SSH 대신 SSM Session Manager 접속을 기본 경로로 둔다
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${local.name}-web"
  role = aws_iam_role.web.name
}

# ─────────────────────────────────────────────────────────────────────────────
# 컴퓨트: 프라이빗 배치, 암호화 EBS, IMDSv2, 시크릿은 user_data 에 넣지 않는다
# ─────────────────────────────────────────────────────────────────────────────
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
  instance_type               = var.instance_type
  subnet_id                   = var.private_subnet_ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.web.name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 강제: SSRF 를 통한 자격증명 탈취 경로 차단
    http_put_response_hop_limit = 1
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    secret_arn = aws_secretsmanager_secret.db.arn
    region     = var.region
  })
  user_data_replace_on_change = true

  tags = { Name = "${local.name}-web" }
}
