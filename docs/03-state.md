# 03. 상태(State) — 원장, 백엔드, 잠금, import / moved

## state가 왜 필요한가

코드에는 `resource "aws_instance" "web"` 만 있고 실제 인스턴스 ID(`i-0abc...`)는 없다.
**코드의 논리 이름 ↔ 실제 리소스 ID 매핑**을 기록하는 것이 state다. 이것이 없으면 Terraform은
"이미 만든 것"과 "새로 만들 것"을 구분하지 못해 매번 새로 만든다.

state에는 그 외에도 리소스의 **모든 속성값**(DB 비밀번호, 프라이빗 키, 접근 키 등 포함)과 의존성 정보가
JSON 평문으로 들어간다.

## 보안 원칙: state는 시크릿이다

| 위험 | 대책 |
|---|---|
| 평문 민감정보 포함 | 원격 백엔드 + 저장 시 암호화(SSE-KMS 등) |
| git 커밋 | `.gitignore` 에 `*.tfstate*`. 이미 올라갔다면 이력까지 제거 + 시크릿 회전 |
| 아무나 읽음 | 백엔드 버킷은 IAM 최소권한, 퍼블릭 접근 차단, 버전 관리로 복구 가능하게 |
| 동시 apply 로 손상 | **잠금(lock)** 지원 백엔드 사용 |
| 출력값으로 노출 | `output` 에 `sensitive = true` (CLI 출력만 마스킹, state 안에는 평문) |

## 백엔드 종류

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-tfstate-prod"
    key            = "network/vpc/terraform.tfstate"   # 프로젝트별 경로 분리
    region         = "ap-northeast-2"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:..."
    dynamodb_table = "terraform-locks"                 # 잠금 (1.10+ 는 use_lockfile = true 로 S3 자체 잠금 가능)
  }
}
```

| 백엔드 | 잠금 | 특징 |
|---|---|---|
| `local` (기본) | 파일 잠금 | 실습용. 팀 사용 불가 |
| `s3` (+DynamoDB) | ✓ | AWS 표준 조합 |
| `azurerm` | ✓ (blob lease) | Azure |
| `gcs` | ✓ | GCP |
| `remote` / `cloud` | ✓ | Terraform Cloud/Enterprise. 실행도 원격에서 |
| `http` | 선택 | GitLab 관리형 state 등 |

백엔드 블록에는 **변수를 쓸 수 없다**. 환경별로는 `-backend-config=prod.hcl` 파일로 주입한다.

## 워크스페이스 vs 디렉터리 분리

- `terraform workspace new prod` → 같은 코드, state 파일만 `env:/prod/...` 로 분리.
- 간단하지만 **prod 와 dev 가 같은 백엔드·같은 권한**을 쓰게 되어 격리가 약하다.
- 실무에서는 환경별 디렉터리(또는 별도 계정) + 별도 백엔드를 더 선호한다.

## 상태 조작 명령

```bash
terraform state list                              # 관리 중인 주소 나열
terraform state show aws_s3_bucket.logs           # 속성 확인 (민감정보 노출 주의)
terraform state mv aws_instance.a aws_instance.b  # 코드 리네임 시 재생성 방지 (구식)
terraform state rm aws_instance.legacy            # 관리에서만 제외 (실제 리소스는 유지)
terraform state pull > backup.json                # 수동 백업
terraform force-unlock <LOCK_ID>                  # 죽은 잠금 해제 (정말 죽었는지 확인 후)
```

## 기존 리소스 가져오기: import

```hcl
# Terraform 1.5+ 선언형 import (plan 에서 미리 확인 가능, CI 친화적)
import {
  to = aws_s3_bucket.legacy
  id = "legacy-bucket-name"
}
```

```bash
terraform plan -generate-config-out=generated.tf   # 속성까지 코드로 생성
```

## 리팩터링: moved / removed 블록

```hcl
# 리소스 이름 변경 또는 모듈로 이동 — state mv 를 코드로 기록
moved {
  from = aws_instance.web
  to   = module.web.aws_instance.this
}

# 1.7+: 관리에서 제외하되 실제 리소스는 남김 (state rm 의 선언형)
removed {
  from = aws_instance.legacy
  lifecycle { destroy = false }
}
```

명령형(`state mv`)보다 코드 리뷰가 가능한 `moved` 를 우선 사용한다.

## 정리

1. state = 매핑 원장 + 전체 속성 스냅샷 → **시크릿으로 취급**.
2. 팀/CI 에서는 원격 백엔드 + 암호화 + 잠금이 필수.
3. 리네임·이동은 `moved`, 기존 자원은 `import` 블록으로 선언적으로 처리한다.
