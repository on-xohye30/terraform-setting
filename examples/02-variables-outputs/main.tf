# 02. 변수 검증 · locals · for/조건 표현식 · sensitive · for_each
#
# 여전히 local 프로바이더만 사용. 각 서버 정의를 "설정 파일" 로 렌더링하며
# 변수 → locals → 리소스 → output 흐름을 익힌다.

terraform {
  required_version = ">= 1.6"
  required_providers {
    local  = { source = "hashicorp/local", version = "~> 2.5" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

locals {
  name_prefix = "${var.project}-${var.env}"
  is_prod     = var.env == "prod"
  out_dir     = "${path.module}/out"

  common_tags = merge(
    {
      Project   = var.project
      Env       = var.env
      ManagedBy = "terraform"
    },
    var.extra_tags,
  )

  # 환경에 따라 기본 인스턴스 크기 매핑
  size_map = {
    small  = local.is_prod ? "m6i.large" : "t3.micro"
    medium = local.is_prod ? "m6i.xlarge" : "t3.small"
    large  = local.is_prod ? "m6i.2xlarge" : "t3.medium"
  }

  # for 표현식: map → map (값 가공)
  servers = {
    for name, s in var.servers : name => merge(s, {
      fqdn          = "${name}.${local.name_prefix}.internal"
      instance_type = local.size_map[s.size]
      # public 서버가 아니면 allowed_cidrs 만 허용
      ingress_cidrs = s.public ? ["0.0.0.0/0"] : var.allowed_cidrs
    })
  }

  # 필터: 공개 서버 이름만
  public_servers = [for name, s in local.servers : name if s.public]

  # prod 에서는 모니터링 미설정 서버를 허용하지 않는다
  unmonitored = [for name, s in local.servers : name if !s.monitor]
}

resource "random_password" "db" {
  count   = var.db_password == "" ? 1 : 0 # 있다/없다 토글에만 count 사용
  length  = 20
  special = false
}

locals {
  db_password = var.db_password != "" ? var.db_password : one(random_password.db[*].result)
}

# for_each: 키 기반 복제 → 서버 하나를 지워도 나머지는 재생성되지 않는다
resource "local_file" "server_config" {
  for_each = local.servers

  filename = "${local.out_dir}/${each.key}.conf"
  content = templatefile("${path.module}/server.conf.tftpl", {
    name   = each.key
    server = each.value
    tags   = local.common_tags
  })

  lifecycle {
    precondition {
      condition     = !(local.is_prod && !each.value.monitor)
      error_message = "prod 환경에서는 모든 서버에 monitor = true 가 필요합니다: ${each.key}"
    }
  }
}

resource "local_sensitive_file" "db_env" {
  filename        = "${local.out_dir}/db.env"
  file_permission = "0600"
  content         = "DB_PASSWORD=${local.db_password}\n"
}
