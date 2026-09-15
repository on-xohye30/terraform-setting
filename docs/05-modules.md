# 05. 모듈 — 재사용 단위 설계

## 모듈이란

`.tf` 파일이 들어있는 디렉터리 하나가 곧 모듈이다. `terraform apply` 를 실행하는 디렉터리가 **루트 모듈**,
루트에서 `module` 블록으로 부른 것이 **자식 모듈**이다.

```hcl
module "log_bucket" {
  source = "./modules/s3-secure-bucket"     # 로컬 경로
  # source  = "terraform-aws-modules/vpc/aws"  # 레지스트리
  # version = "~> 5.0"                          # 레지스트리 소스만 version 지원
  # source  = "git::https://github.com/org/repo.git//modules/x?ref=v1.2.0"  # git + 서브디렉터리 + 태그 고정

  bucket_name = "${local.name_prefix}-logs"
  tags        = local.common_tags
}

output "log_bucket_arn" {
  value = module.log_bucket.arn
}
```

## 표준 파일 구성

```
modules/s3-secure-bucket/
├── main.tf        # 리소스
├── variables.tf   # 입력 계약
├── outputs.tf     # 출력 계약
├── versions.tf    # required_providers (모듈은 provider 블록을 갖지 않는다)
└── README.md      # 사용법 (terraform-docs 로 자동 생성 가능)
```

## 설계 원칙

1. **모듈 안에서 provider 블록을 선언하지 않는다.** 루트가 넘겨준다(멀티 리전은 `providers = { aws = aws.seoul }`).
2. **보안 기본값을 모듈에 굽는다.** 사용자가 아무 옵션도 안 줘도 암호화·퍼블릭 차단·버전 관리가 켜지도록.
   → 조직 표준을 코드로 강제하는 가장 효과적인 방법.
3. 입력은 최소로, 필요한 것만 `variable` 로 열고 `validation` 을 단다.
4. 출력은 **다른 모듈이 참조할 식별자(id, arn, name)** 중심으로.
5. 하나의 모듈은 하나의 책임(버킷, VPC, IAM 역할). "전체 스택 모듈"은 재사용성이 없다.
6. 외부 모듈은 `version`/`ref` 로 **반드시 고정**한다. 공급망 리스크(모듈 소스 변조)를 줄인다.

## 반복: count vs for_each

```hcl
# 나쁜 예 — 중간 요소를 지우면 뒤 인덱스가 밀려 재생성됨
module "bucket" {
  count       = length(var.bucket_names)
  source      = "./modules/s3-secure-bucket"
  bucket_name = var.bucket_names[count.index]
}

# 좋은 예 — 키 기반이라 안정적
module "bucket" {
  for_each    = toset(var.bucket_names)
  source      = "./modules/s3-secure-bucket"
  bucket_name = each.key
}
# 접근: module.bucket["logs"].arn
```

`count` 는 "있다/없다" 토글(`count = var.enabled ? 1 : 0`)에만 쓰는 편이 안전하다.

## 모듈 변경 시 알아둘 것

- 모듈 소스/버전 변경 후에는 `terraform init -upgrade` 필요.
- 모듈 내부 리소스 주소는 `module.<name>.<type>.<name>` 이므로 모듈로 옮기면 주소가 바뀐다 → `moved` 블록으로 재생성 방지.
- `terraform-docs markdown . > README.md` 로 입력/출력 표를 자동 생성해두면 계약이 문서화된다.

## 실습

→ `examples/03-modules` : 보안 기본값이 굳어진 S3 버킷 모듈을 만들고 두 번 호출한다.
