# Security Decision Records

형식: 배경 → 결정 → 결과/트레이드오프. 번호는 `.checkov.yaml` 과 코드 주석에서 참조한다.

---

## ADR-001 · state 는 시크릿으로 취급한다

**배경.** Terraform state 는 리소스의 전체 속성을 JSON 평문으로 저장한다. `sensitive = true` 는 CLI 출력만 가릴 뿐 state 내부는 평문이다.
state 가 유출되면 DB 비밀번호, 내부 IP 구조, IAM 구성이 그대로 노출된다.

**결정.**
- state 는 `bootstrap` 이 만드는 전용 버킷에만 둔다. 버킷은 `s3-secure-bucket` 모듈로 생성해 퍼블릭 차단·암호화·TLS 전용·버전 관리를 상속받는다.
- 잠금 테이블과 버킷에 `prevent_destroy` / `deletion_protection` 을 건다.
- state 접근은 `state_access` IAM 정책으로 명시된 주체에만 부여한다.
- `*.tfstate*`, `tfplan*`, `backend.hcl` 은 `.gitignore` 로 커밋을 막는다.

**결과.** 스택마다 `key` 를 분리해 blast radius 를 줄였다. 트레이드오프로 bootstrap 은 로컬 state 로 1회 실행해야 하는 닭-달걀 문제가 있으며, 실행 후 `init -migrate-state` 로 자기 버킷에 옮기는 절차를 README 에 명시했다.

---

## ADR-002 · 암호화 기본값은 SSE-S3, CMK 는 옵션

**배경.** 모든 버킷·시크릿에 KMS CMK 를 강제하면 키 관리 모듈이 선행돼야 하고, 키 정책 오류가 곧 장애가 된다.

**결정.** 모듈은 저장 암호화를 **항상** 켜되, `kms_key_arn` 이 주어지면 SSE-KMS(+Bucket Key), 없으면 SSE-S3 를 사용한다.
같은 원칙을 DynamoDB 잠금 테이블, Secrets Manager, RDS Performance Insights 에도 적용한다(AWS 관리 키로 암호화).
checkov 의 CMK 강제 검사 `CKV_AWS_119`, `CKV_AWS_149`, `CKV_AWS_354` 는 이 결정을 근거로 스킵한다.

**결과.** "암호화 없음" 상태는 생성 자체가 불가능하다. CMK 가 필요한 데이터 등급은 호출자가 한 줄로 상향할 수 있다. KMS 모듈 도입 후 스킵을 제거하는 것이 로드맵 1순위다.

---

## ADR-003 · 시크릿은 생성·보관·조회를 분리한다

**배경.** 취약점 분석에서 가장 흔한 IaC 결함은 `password = "..."`, `user_data` 내 자격증명, `output` 으로 노출되는 시크릿이다.

**결정.**
- 생성: `random_password` (Terraform 이 만들고 사람은 모른다)
- 보관: Secrets Manager. 접속 정보(host/port/dbname)까지 JSON 으로 함께 저장해 앱이 한 번에 읽는다.
- 조회: 인스턴스 역할이 **해당 시크릿 ARN 에만** `GetSecretValue` 를 갖는다. user_data 에는 ARN 만 전달한다.
- `output` 은 값이 아니라 ARN 만 노출한다.
- RDS 의 `password` 는 `ignore_changes` 로 두어 회전이 Terraform 밖(Secrets Manager 회전)에서 일어나도 drift 가 생기지 않게 한다.

**결과.** 비밀번호가 코드·PR·CI 로그에 나타나지 않는다. 남는 한계는 `random_password.result` 가 state 에 저장된다는 점이며(ADR-001 로 보호), Terraform 1.10 의 `ephemeral` 로 전환하는 것이 로드맵이다.

---

## ADR-004 · 네트워크 접근은 CIDR 이 아니라 보안그룹 참조로

**배경.** DB 인바운드에 웹 서브넷 CIDR 을 적으면 같은 서브넷의 다른 워크로드도 DB 에 닿는다. 인스턴스가 늘거나 서브넷이 바뀔 때마다 규칙을 손봐야 한다.

**결정.** `aws_vpc_security_group_ingress_rule.db_from_web` 은 `referenced_security_group_id = aws_security_group.web.id` 로 정의한다.
관리 접근(22)은 `admin_cidrs` 변수로 받되 `validation` 에서 `0.0.0.0/0` 을 거부하고, SSM Session Manager 를 기본 경로로 둔다.

**결과.** "웹 티어만 DB 에 접근" 이 코드에 그대로 표현된다. 443 전체 개방은 공개 서비스의 의도된 동작이므로 tfsec 인라인 예외로 사유를 남겼다.

---

## ADR-005 · IMDSv2 강제

**배경.** IMDSv1 은 SSRF 한 번으로 인스턴스 역할 자격증명을 탈취당하는 대표 경로다(Capital One 사고 패턴).

**결정.** 모든 인스턴스에 `http_tokens = "required"`, `http_put_response_hop_limit = 1`. Conftest 정책으로도 plan 단계에서 재검사한다.

**결과.** 컨테이너 내부에서 메타데이터 접근이 필요한 경우 hop limit 을 2 로 올려야 하며, 이때는 PR 에서 사유를 요구한다.

---

## ADR-006 · 검증은 정적 스캐너 2종 + plan 정책으로 겹친다

**배경.** 스캐너마다 사각지대가 다르다. tfsec 은 빠르지만 규칙이 적고, checkov 는 규칙이 많지만 노이즈가 있다. 둘 다 변수에 실제 어떤 값이 들어오는지는 모른다.

**결정.**
- PR 마다 `fmt → validate → tfsec(HIGH+) → checkov → conftest verify` 를 실행한다.
- 배포 직전 `conftest test tfplan.json` 으로 최종 값 기준 정책을 검사한다.
- 예외는 **해당 줄의 사유 주석** 또는 `.checkov.yaml` 의 사유 있는 스킵만 허용한다. 사유 없는 예외는 리뷰에서 거부한다.

**결과.** "스캐너가 통과했으니 안전" 이 아니라 "이 규칙들을 왜 통과/예외 처리했는지" 가 코드에 남는다. 정책 자체도 `conftest verify` 로 테스트해 정책 회귀를 막는다.

---

## ADR-007 · 삭제 보호는 데이터 리소스에 기본 적용

**배경.** `terraform destroy` 나 잘못된 `-/+` 재생성 한 번으로 DB·state 가 사라질 수 있다.

**결정.** RDS(`deletion_protection`, `prevent_destroy`, 최종 스냅샷), state 버킷(`prevent_destroy`), 잠금 테이블(`deletion_protection_enabled`, `prevent_destroy`) 에 적용한다. 백업 버킷 `force_destroy` 는 기본 `false`.

**결과.** 의도적 삭제는 두 단계(코드에서 보호 해제 → apply → destroy)가 필요하다. 개발 환경의 빠른 정리에는 불편하지만, 그 불편이 목적이다.
