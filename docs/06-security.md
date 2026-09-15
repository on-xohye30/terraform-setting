# 06. IaC 보안 — Terraform 코드에서 위험 찾기

Terraform 코드는 "인프라 설정의 소스코드"다. 따라서 **코드 리뷰만으로 배포 전에 설정 오류(misconfiguration)를 잡을 수 있다**는 것이 IaC의 가장 큰 보안적 이점이다.
반대로 잘못된 모듈 하나가 수백 개 리소스에 같은 취약점을 복제하기도 한다.

## 점검 계층

| 계층 | 대상 | 도구 |
|---|---|---|
| 정적 분석 (배포 전) | .tf 코드 | tfsec, checkov, trivy config, KICS, terrascan |
| 정책 강제 (plan 단계) | plan JSON | OPA/conftest, Sentinel(TFC), checkov `-f tfplan.json` |
| 시크릿 탐지 | 코드·tfvars·state | gitleaks, trufflehog |
| 런타임 (배포 후) | 실제 클라우드 | AWS Config, Security Hub, Prowler, ScoutSuite |
| 드리프트 | 코드 ↔ 실제 | `terraform plan` 주기 실행, driftctl |

## 취약 패턴 카탈로그 (자주 나오는 것)

### 1. 네트워크 전체 개방
```hcl
ingress {
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]      # ✗ SSH 전세계 개방
}
```
→ 관리 CIDR 제한, 또는 SSM Session Manager 로 대체. `validation` 으로 0.0.0.0/0 자체를 막을 수 있다.

### 2. 스토리지 퍼블릭 노출
```hcl
resource "aws_s3_bucket_acl" "b" { acl = "public-read" }                       # ✗
resource "aws_s3_bucket_public_access_block" "b" { block_public_acls = false }  # ✗
```
→ `aws_s3_bucket_public_access_block` 4개 옵션 모두 true. 정적 웹은 CloudFront OAC 로.

### 3. 저장/전송 암호화 누락
```hcl
resource "aws_db_instance" "db" { storage_encrypted = false }   # ✗
resource "aws_ebs_volume" "v"   { encrypted = false }           # ✗
resource "aws_lb_listener" "l"  { protocol = "HTTP" }           # ✗ (리다이렉트 용도 제외)
```

### 4. 하드코딩 시크릿
```hcl
resource "aws_db_instance" "db" {
  password = "P@ssw0rd123"          # ✗ 코드·state·plan 에 모두 남는다
}
provider "aws" {
  access_key = "AKIA..."            # ✗ 절대 금지
}
```
→ `random_password` + Secrets Manager, `data "aws_ssm_parameter"`, Vault provider, `ephemeral`(1.10+) 사용.
   프로바이더 인증은 환경변수/프로파일/OIDC(CI) 로.

### 5. IAM 과도 권한
```hcl
policy = jsonencode({
  Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]   # ✗
})
```
→ 최소권한. `aws_iam_policy_document` data 소스로 구조화하고, Access Analyzer 로 생성된 정책 참고.

### 6. 로깅·모니터링 미설정
- S3 액세스 로그, CloudTrail, VPC Flow Logs, RDS 감사 로그 미설정 → 사고 시 추적 불가.

### 7. 삭제 보호 부재
```hcl
lifecycle { prevent_destroy = true }   # 프로덕션 DB·state 버킷에는 필수
deletion_protection = true             # RDS, DynamoDB, ALB
```

### 8. 공급망
- 모듈 `source` 에 버전/ref 미고정 → 상류 변조 시 그대로 유입.
- 프로바이더 `version` 미고정, `.terraform.lock.hcl` 미커밋.
- `local-exec` / `remote-exec` 프로비저너에서 외부 스크립트 `curl | sh`.

### 9. 출력·상태를 통한 정보 노출
- `output` 에 비밀번호를 `sensitive` 없이 노출.
- state 버킷이 퍼블릭이거나 개발자 전원이 읽기 가능.
- CI 로그에 `terraform show` 로 state 를 덤프.

## 스캐너 사용법

```bash
# tfsec (Aqua) — 빠르고 결과가 읽기 쉬움
tfsec ./examples/05-security-scan
tfsec . --format json --out tfsec.json --minimum-severity HIGH

# checkov — 규칙 수가 많고 plan JSON 도 검사 가능
checkov -d ./examples/05-security-scan
terraform plan -out tfplan && terraform show -json tfplan > tfplan.json
checkov -f tfplan.json

# trivy — 컨테이너/IaC 통합
trivy config ./examples/05-security-scan
```

특정 검사를 예외 처리할 때는 **사유를 주석으로 남긴다.**
```hcl
#tfsec:ignore:aws-s3-enable-bucket-logging 로그 버킷 자체이므로 순환 로깅 제외
#checkov:skip=CKV_AWS_18:same reason
```

## 리뷰 체크리스트 (PR 볼 때)

- [ ] plan 에 `-/+` (재생성) 이 있는가? 데이터 리소스인가?
- [ ] `0.0.0.0/0`, `::/0`, `public-read`, `"*"` 문자열이 새로 들어왔는가?
- [ ] 새 리소스에 암호화·로깅·태그가 있는가?
- [ ] 시크릿이 리터럴로 들어갔는가? (`password`, `secret`, `token`, `key` 검색)
- [ ] 모듈/프로바이더 버전이 고정돼 있는가?
- [ ] `lifecycle.ignore_changes` 로 보안 설정을 무시하고 있지 않은가?
- [ ] 스캐너 예외(ignore/skip) 에 사유가 있는가?

## 실습

→ `examples/05-security-scan` : 일부러 취약하게 만든 코드에서 위 패턴을 찾고, 스캐너 결과와 비교한 뒤 고쳐본다.
