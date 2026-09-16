# policy

`terraform show -json` 으로 뽑은 plan 에 적용하는 OPA(Rego) 정책. tfsec·checkov 가 **코드 문자열** 을 보는 반면,
이 정책은 **변수·모듈이 해석된 최종 값** 을 본다. 예를 들어 `cidr_ipv4 = var.admin_cidr` 에 실제로 `0.0.0.0/0` 이
들어왔는지는 plan 단계에서만 알 수 있다.

## 규칙

| 영역 | 규칙 |
|---|---|
| 네트워크 | 22/3389 를 `0.0.0.0/0` 에 개방 금지, 모든 프로토콜(`-1`) 전체 개방 금지 |
| S3 | public access block 4개 모두 `true`, 퍼블릭 ACL 금지 |
| RDS | 저장 암호화 필수, 공개 접근 금지, 삭제 보호 필수 |
| EC2 | IMDSv2(`http_tokens = required`) 필수, 루트 볼륨 암호화 필수 |
| IAM | `Action "*"` + `Resource "*"` 허용 정책 금지 |

생성·변경(`create`, `update`) 되는 리소스만 검사하고 삭제는 제외한다.

## 실행

```bash
# 정책 단위 테스트 (CI 에서 실행)
conftest verify -p policy

# 실제 plan 검사
cd stacks/web-db
terraform plan -var-file=prod.tfvars -out=tfplan
terraform show -json tfplan > tfplan.json
conftest test tfplan.json -p ../../policy
```

## 규칙 추가 방법

1. `terraform.rego` 에 `deny contains msg if { ... }` 블록 추가
2. `terraform_test.rego` 에 위반 케이스와 통과 케이스를 **한 쌍으로** 추가
3. `conftest verify -p policy` 통과 확인 후 PR
