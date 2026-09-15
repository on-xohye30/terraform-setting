# 04. 변수 · 출력 · locals · 표현식

## variable

```hcl
variable "env" {
  description = "배포 환경"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "stage", "prod"], var.env)
    error_message = "env 는 dev/stage/prod 중 하나여야 합니다."
  }
}

variable "db_password" {
  type      = string
  sensitive = true          # plan/apply 출력에서 마스킹. state 에는 평문 저장됨!
  ephemeral = true          # 1.10+: state/plan 에도 저장하지 않음 (프로바이더가 지원할 때)
}

variable "allowed_cidrs" {
  type = list(string)
  validation {
    condition     = !contains(var.allowed_cidrs, "0.0.0.0/0")
    error_message = "전체 개방(0.0.0.0/0)은 허용하지 않습니다."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "server" {
  type = object({
    name    = string
    size    = optional(string, "t3.micro")   # optional + 기본값
    monitor = optional(bool, true)
  })
}
```

### 값 주입 우선순위 (낮음 → 높음)

1. `default`
2. 환경변수 `TF_VAR_env=prod`
3. `terraform.tfvars` / `terraform.tfvars.json`
4. `*.auto.tfvars` (알파벳 순)
5. `-var-file=...` / `-var key=val` (명령줄 순서대로, 뒤가 이김)

시크릿은 tfvars 파일에 적지 말고 **환경변수(`TF_VAR_...`)나 Vault/SSM 의 data 소스**로 가져온다.

## output

```hcl
output "bucket_name" {
  description = "생성된 버킷 이름"
  value       = aws_s3_bucket.this.bucket
}

output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true                # sensitive 값을 참조하면 output 도 sensitive 여야 함
}
```

- 루트 모듈의 output 은 `terraform output -json` 으로 다른 파이프라인 단계에 넘길 수 있다.
- 자식 모듈의 output 은 `module.<name>.<output>` 으로만 접근 가능. 모듈은 output 으로 선언한 것만 노출한다.

## locals

```hcl
locals {
  name_prefix = "${var.project}-${var.env}"
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Env       = var.env
  })
  is_prod = var.env == "prod"
}
```

반복되는 계산, 조건 플래그, 태그 병합에 사용. 변수와 달리 외부에서 주입 불가.

## 자주 쓰는 표현식

```hcl
# 조건
instance_type = local.is_prod ? "m6i.large" : "t3.micro"

# for 표현식 — list → list
upper_names = [for n in var.names : upper(n)]

# list → map
name_to_arn = { for b in aws_s3_bucket.buckets : b.bucket => b.arn }

# 필터
public_subnets = [for s in var.subnets : s.id if s.public]

# splat
ids = aws_instance.web[*].id

# 동적 블록 — 반복되는 중첩 블록 생성
dynamic "ingress" {
  for_each = var.ingress_rules
  content {
    from_port   = ingress.value.port
    to_port     = ingress.value.port
    protocol    = "tcp"
    cidr_blocks = ingress.value.cidrs
  }
}
```

## 자주 쓰는 내장 함수

| 분류 | 함수 |
|---|---|
| 문자열 | `format`, `join`, `split`, `replace`, `lower/upper`, `trimspace`, `substr`, `regex` |
| 컬렉션 | `length`, `concat`, `merge`, `lookup`, `keys/values`, `flatten`, `distinct`, `contains`, `toset/tolist/tomap`, `zipmap` |
| 인코딩 | `jsonencode/jsondecode`, `yamlencode/yamldecode`, `base64encode`, `templatefile` |
| 파일 | `file`, `fileexists`, `filebase64`, `filemd5` |
| 네트워크 | `cidrsubnet`, `cidrhost`, `cidrnetmask` |
| 타입 | `can`, `try`, `coalesce`, `one`, `sensitive/nonsensitive` |

`terraform console` 에서 바로 실험할 수 있다:

```
> cidrsubnet("10.0.0.0/16", 8, 3)
"10.0.3.0/24"
> try(var.missing, "fallback")
```

## 실습

→ `examples/02-variables-outputs`
