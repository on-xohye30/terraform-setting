# 01. 핵심 개념 — HCL, 블록, 프로바이더, 리소스 그래프

## Terraform이 하는 일

Terraform은 **선언형 IaC(Infrastructure as Code)** 도구다. 원하는 최종 상태를 HCL로 적으면,
Terraform이 (1) 현재 상태(state)와 (2) 실제 인프라를 조회한 뒤 (3) 코드와의 차이를 계산해
필요한 API 호출만 수행한다. 절차(스크립트)를 쓰는 것이 아니라 결과를 쓴다는 점이 셸 스크립트와 다르다.

```
   코드(.tf)  ──┐
                ├─► plan(차이 계산) ─► apply(API 호출) ─► state 갱신
   state ──────┘        ▲
                        └── refresh(실제 인프라 조회)
```

## HCL 문법 최소 단위

```hcl
# 블록: <블록타입> "<라벨1>" "<라벨2>" { ... }
resource "aws_s3_bucket" "logs" {
  bucket = "my-log-bucket"        # 인자(argument): 이름 = 표현식

  tags = {                        # 맵
    Env  = "dev"
    Team = "sec"
  }

  lifecycle {                     # 중첩 블록
    prevent_destroy = true
  }
}
```

- 값 타입: `string`, `number`, `bool`, `list(...)`, `set(...)`, `map(...)`, `object({...})`, `tuple([...])`, `any`
- 문자열 보간: `"bucket-${var.env}"`, 히어독: `<<-EOT ... EOT`
- 주석: `#`, `//`, `/* */`
- 참조: `resource_type.name.attribute`, `var.x`, `local.x`, `module.m.output`, `data.type.name.attr`

## 핵심 블록

| 블록 | 역할 | 예 |
|---|---|---|
| `terraform` | Terraform 자체 설정. 버전, 프로바이더 요구사항, 백엔드 | `required_version = ">= 1.6"` |
| `provider` | 특정 플랫폼 API와 통신하는 플러그인 설정 | `provider "aws" { region = "ap-northeast-2" }` |
| `resource` | 생성·변경·삭제할 관리 대상 | `resource "aws_instance" "web" {}` |
| `data` | 이미 존재하는 것을 **읽기만** | `data "aws_ami" "al2023" {}` |
| `variable` | 입력값 | `variable "env" { type = string }` |
| `output` | 결과값 노출(다른 모듈/CLI에서 사용) | `output "bucket_arn" {}` |
| `locals` | 내부용 계산 값 | `locals { name = "${var.project}-${var.env}" }` |
| `module` | 다른 디렉터리의 코드 호출 | `module "vpc" { source = "./modules/vpc" }` |

## 프로바이더 버전 고정이 중요한 이유

```hcl
terraform {
  required_version = "~> 1.6"          # 1.6.x 만 허용 (1.7 X)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"               # 5.x 허용, 6.0 X
    }
  }
}
```

- 프로바이더는 자주 **breaking change**를 낸다. 버전을 안 잠그면 어느 날 plan이 대량 변경을 출력한다.
- `terraform init` 이 만드는 `.terraform.lock.hcl` 은 정확한 버전+해시를 기록한다. 팀 프로젝트라면 커밋해서 재현성을 확보한다
  (이 학습 저장소는 개인 실습이라 ignore 처리함).

## 리소스 그래프와 의존성

Terraform은 모든 리소스를 **DAG(방향 비순환 그래프)** 로 만들고 의존성이 없는 것은 병렬(기본 10개)로 처리한다.

- **암묵적 의존성**: 속성 참조만 하면 자동으로 순서가 잡힌다.
  ```hcl
  resource "aws_s3_bucket_versioning" "v" {
    bucket = aws_s3_bucket.logs.id      # → logs 가 먼저 생성됨
  }
  ```
- **명시적 의존성**: 참조가 없는데 순서가 필요할 때만 `depends_on`.
  ```hcl
  depends_on = [aws_iam_role_policy.app]
  ```
- `terraform graph | dot -Tpng > graph.png` 로 그래프를 시각화할 수 있다.

## 메타 인자 (모든 리소스에 공통)

| 메타 인자 | 용도 |
|---|---|
| `count` | 개수로 복제. 인덱스 기반이라 중간 삭제 시 뒤 요소가 밀려 재생성됨 |
| `for_each` | map/set 키 기반 복제. **중간 삭제에 안전** → 실무에서는 대부분 for_each 선호 |
| `provider` | 여러 프로바이더 별칭(alias) 중 선택 (예: 멀티 리전) |
| `depends_on` | 명시적 순서 |
| `lifecycle` | `create_before_destroy`, `prevent_destroy`, `ignore_changes`, `replace_triggered_by` |

## 정리

- HCL은 "블록 + 인자 + 표현식"만 알면 대부분 읽힌다.
- 선언형이므로 "실행 순서"가 아니라 "참조 관계"를 설계하는 것이 핵심이다.
- 버전 고정과 lock 파일은 재현성의 시작점이다.
