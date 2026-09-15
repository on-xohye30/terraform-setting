# 05. security-scan — 취약한 IaC 찾기와 고치기

```
05-security-scan/
├── insecure/main.tf   # 일부러 취약하게 (18개 주석 번호)  — apply 금지
└── secure/main.tf     # 같은 구성의 안전한 버전
```

## 1) 먼저 눈으로

`insecure/main.tf` 를 열고 `docs/06-security.md` 의 카탈로그를 보지 않은 채 문제를 최대한 찾아 적는다.
그다음 주석의 `[n]` 번호와 대조한다.

## 2) 스캐너로

```bash
# 설치 (택1)
brew install tfsec checkov trivy
# 또는 pip install checkov / winget install Aquasecurity.tfsec

tfsec ./insecure
tfsec ./insecure --format json --out insecure-tfsec.json
checkov -d ./insecure --compact
trivy config ./insecure
```

각 스캐너가 **무엇을 잡고 무엇을 못 잡는지** 비교한다. 예:

| 문제 | tfsec | checkov | 비고 |
|---|---|---|---|
| 0.0.0.0/0 ingress | ✓ | ✓ | |
| 퍼블릭 ACL / access block | ✓ | ✓ | |
| 하드코딩 password | ✓ (일부) | ✓ (CKV_SECRET) | 정적 문자열만. 변수 통해 들어오면 못 잡음 |
| provider access_key | △ | ✓ | gitleaks 가 더 확실 |
| `curl \| bash` in user_data | ✗ | ✗ | 스캐너 사각지대 → 코드 리뷰 필요 |
| IMDSv1 | ✓ | ✓ | |
| output 에 시크릿 | △ | ✗ | sensitive 누락은 terraform 자체가 오류로 잡아줌(참조가 sensitive 일 때만) |
| 버전 미고정 | ✗ | ✗ | 정책(OPA) 또는 리뷰 |

→ **스캐너는 필요조건이지 충분조건이 아니다.** 사각지대(공급망, 로직, 컨텍스트)는 사람이 본다.

## 3) 고친 버전 검증

```bash
cd secure
terraform init -backend=false
terraform validate
tfsec .
checkov -d .
```

남는 지적이 있다면 (예: 443 전체 개방) 의도된 것인지 판단하고 사유와 함께 예외 처리:

```hcl
#tfsec:ignore:aws-ec2-no-public-ingress-sgr 공개 HTTPS 서비스 포트
```

## 4) plan 기반 정책 검사 (선택)

```bash
terraform plan -out tfplan && terraform show -json tfplan > tfplan.json
checkov -f tfplan.json               # 변수가 해석된 최종 값 기준으로 검사
conftest test tfplan.json -p policy/ # OPA Rego 정책 (직접 작성)
```

## 핵심 정리

- IaC 스캔은 **PR 단계**에 넣어야 가치가 있다. 배포 후 발견은 이미 노출된 뒤다.
- 하드코딩 시크릿은 코드에서 지워도 **git 이력과 state** 에 남는다. 회전이 답이다.
- 가장 효과적인 수정은 개별 리소스를 고치는 것이 아니라 **보안 기본값 모듈로 교체**하는 것(secure 버전의 S3 부분).
