# 02. 워크플로 — init / validate / plan / apply / destroy

## 표준 사이클

```
terraform init      ─ 작업 디렉터리 초기화 (프로바이더·모듈 다운로드, 백엔드 연결)
terraform fmt       ─ 코드 포맷 정리 (CI에서 -check 로 강제)
terraform validate  ─ 문법·타입·참조 오류 검사 (API 호출 없음)
terraform plan      ─ 변경 계획 출력 (-out=tfplan 으로 저장 가능)
terraform apply     ─ 계획 적용 (저장된 tfplan 을 주면 재확인 없이 그대로 적용)
terraform destroy   ─ 관리 중인 리소스 전부 삭제 (= plan -destroy + apply)
```

## 각 단계에서 생기는 파일

| 파일/디렉터리 | 생성 시점 | 커밋? | 설명 |
|---|---|---|---|
| `.terraform/` | init | ✗ | 다운로드된 프로바이더 바이너리, 모듈 캐시 |
| `.terraform.lock.hcl` | init | 팀이면 ✓ | 프로바이더 정확한 버전+체크섬 |
| `terraform.tfstate` | apply | **절대 ✗** | 현재 상태. 민감정보 평문 포함 가능 |
| `terraform.tfstate.backup` | apply | ✗ | 직전 상태 백업 |
| `tfplan` (임의 이름) | plan -out | ✗ | 바이너리 계획. 민감정보 포함 가능 |
| `*.tfvars` | 수동 | 값에 따라 | 변수 값. 시크릿 들어가면 ✗ |

## plan 출력 읽는 법

```
  # aws_s3_bucket.logs will be created
  + resource "aws_s3_bucket" "logs" {
      + bucket = "my-log-bucket"
      + id     = (known after apply)
    }

  # aws_instance.web must be replaced
-/+ resource "aws_instance" "web" {
      ~ ami = "ami-aaa" -> "ami-bbb" # forces replacement
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

| 기호 | 의미 | 주의 |
|---|---|---|
| `+` | 생성 | |
| `~` | 제자리 수정 | |
| `-` | 삭제 | 데이터 손실 확인 |
| `-/+` | **삭제 후 재생성** | DB·버킷이면 위험. `forces replacement` 를 반드시 확인 |
| `+/-` | 생성 후 삭제 (`create_before_destroy`) | |
| `<=` | data 소스 읽기 | |

`(known after apply)` 는 apply 이후에야 확정되는 값. 이 값을 다른 리소스의 `count`/`for_each` 키에 쓰면 오류가 난다.

## 실무형 흐름 (CI/CD)

```
PR 생성 ──► fmt -check ──► validate ──► tfsec/checkov ──► plan (-out) ──► 리뷰어가 plan 확인
                                                                         │
merge ─────────────────────────────────────────────────────────────────► apply tfplan
```

- **plan 과 apply 를 분리**하고, 리뷰된 plan 파일을 그대로 apply 하는 것이 핵심. 사이에 상태가 바뀌면 apply가 거부된다.
- `-lock-timeout=5m`, `-input=false`, `-no-color` 는 CI에서 거의 항상 붙인다.

## 자주 쓰는 옵션

```bash
terraform plan -var="env=dev" -var-file=dev.tfvars
terraform plan -target=module.vpc            # 특정 리소스만 (비상시만. 상태 드리프트 원인)
terraform apply -auto-approve                # 확인 프롬프트 생략 (CI 또는 실습용)
terraform apply -replace=aws_instance.web    # 강제 재생성 (구 taint)
terraform plan -refresh-only                 # 코드 변경 없이 실제↔상태 차이만 반영
terraform show -json tfplan | jq             # 계획을 JSON으로 (정책 검사·리포트용)
```

## 드리프트(drift)

콘솔에서 누가 손으로 바꾸면 코드 ≠ 실제 가 된다. `plan` 시 refresh 단계에서 감지되며,
코드대로 되돌릴지(`apply`) 실제를 받아들일지(`-refresh-only` 후 코드 수정) 결정해야 한다.
보안 관점에서 드리프트는 **"누가 승인 없이 인프라를 바꿨다"** 는 신호이기도 하다.
