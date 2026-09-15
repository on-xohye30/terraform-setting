# Terraform 구현 학습

Terraform으로 인프라를 **코드로 선언하고(HCL) → 계획하고(plan) → 적용하고(apply) → 상태로 추적(state)** 하는
전체 흐름을 직접 구현하며 정리한 학습 저장소입니다. 클라우드 계정 없이도 돌아가는 `local` 프로바이더 예제부터
시작해서, 변수/출력 → 모듈 → 원격 상태 → IaC 보안 점검까지 단계별로 확장합니다.

> 보안 분석 업무 관점에서 **"Terraform 코드를 읽고 위험한 설정을 찾아내는 눈"**을 기르는 것도 함께 목표로 합니다.
> (`docs/06-security.md`, `examples/05-security-scan`)

## 학습 목표

1. HCL 문법과 Terraform 핵심 블록(`terraform`, `provider`, `resource`, `data`, `variable`, `output`, `locals`, `module`)을 설명할 수 있다.
2. `init → validate → plan → apply → destroy` 워크플로와 각 단계에서 생기는 파일을 이해한다.
3. **state**가 무엇이고 왜 민감정보 취급을 해야 하는지, 원격 백엔드 + 잠금(lock)이 왜 필요한지 설명할 수 있다.
4. 재사용 가능한 모듈을 작성하고 입력/출력 계약을 설계할 수 있다.
5. tfsec / checkov / trivy 같은 도구로 IaC 설정 오류를 자동 점검하고, 대표 취약 패턴을 식별할 수 있다.

## 디렉터리 구조

```
terraform-setting/
├── README.md
├── docs/                         # 개념 정리 노트
│   ├── 01-core-concepts.md       # HCL, 블록, 프로바이더, 리소스 그래프
│   ├── 02-workflow.md            # init/plan/apply/destroy 와 생성 파일
│   ├── 03-state.md               # 상태 파일, 백엔드, 잠금, import/moved
│   ├── 04-variables-outputs.md   # 변수 타입/검증/민감값, 출력, locals, 함수
│   ├── 05-modules.md             # 모듈 설계, 버전 고정, for_each/count
│   ├── 06-security.md            # IaC 보안 점검 포인트 + 취약 패턴 카탈로그
│   └── 07-cheatsheet.md          # 명령어/함수 치트시트
└── examples/
    ├── 01-local-basics/          # 클라우드 없이 실행: local_file 로 흐름 익히기
    ├── 02-variables-outputs/     # 변수 검증, sensitive, locals, for 표현식
    ├── 03-modules/               # 보안 기본값이 적용된 S3 버킷 모듈 (AWS)
    ├── 04-remote-state/          # S3 + DynamoDB 잠금 백엔드 구성
    └── 05-security-scan/         # 일부러 취약하게 만든 코드 + 스캐너 실행법
```

## 빠른 시작 (클라우드 계정 불필요)

```bash
# Terraform 설치 확인
terraform -version

cd examples/01-local-basics
terraform init          # 프로바이더 다운로드, .terraform/ 생성
terraform validate      # 문법/타입 검증
terraform plan          # 변경 계획 미리보기 (아무것도 바꾸지 않음)
terraform apply         # 실제 적용 → terraform.tfstate 생성
cat out/hello.txt

terraform destroy       # 생성한 리소스 정리
```

## 핵심 요약 (한 장 정리)

| 개념 | 한 줄 요약 |
|---|---|
| 선언형 | "어떻게"가 아니라 "최종 상태"를 적으면 Terraform이 차이(diff)를 계산해 맞춘다 |
| 프로바이더 | AWS/Azure/GCP/local 등 API 플러그인. `required_providers`로 버전 고정 |
| 리소스 | 관리 대상 객체. `resource "<type>" "<name>"`, 참조는 `type.name.attr` |
| 상태(state) | 실제 인프라 ↔ 코드 매핑 원장. **평문 민감정보 포함** → 원격 저장 + 암호화 + 접근통제 필수 |
| plan | 코드·상태·실제를 비교해 `+ 생성 / ~ 변경 / - 삭제 / -/+ 재생성` 계획 출력 |
| 모듈 | 디렉터리 단위 재사용. 입력(variable)·출력(output)이 계약 |
| 워크스페이스 | 같은 코드로 dev/stage/prod 상태만 분리 |
| 보안 점검 | tfsec·checkov·trivy로 공개 버킷, 0.0.0.0/0, 암호화 미적용, 하드코딩 시크릿 탐지 |

## 학습 순서 추천

`docs/01` → `examples/01` → `docs/02`, `docs/03` → `examples/02` → `docs/04` → `docs/05` + `examples/03`
→ `examples/04` → `docs/06` + `examples/05` → `docs/07`은 수시 참조

## 참고 자료

- Terraform 공식 문서: https://developer.hashicorp.com/terraform/docs
- Terraform Registry (프로바이더/모듈): https://registry.terraform.io/
- AWS Provider 문서: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- tfsec: https://github.com/aquasecurity/tfsec · checkov: https://www.checkov.io/ · trivy: https://trivy.dev/
- OpenTofu(오픈소스 포크): https://opentofu.org/
