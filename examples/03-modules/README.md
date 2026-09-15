# 03. modules — 보안 기본값 S3 모듈

`modules/s3-secure-bucket` 은 호출자가 아무 옵션도 주지 않아도
퍼블릭 차단·암호화·버전 관리·TLS 강제·수명주기가 켜지는 모듈이다.
루트(`main.tf`)에서 로그 버킷 1개 + 데이터 버킷 2개(for_each)를 만든다.

## 자격증명 없이 할 수 있는 것

```bash
terraform init
terraform fmt -recursive -check
terraform validate
tfsec .          # 모듈 자체가 스캐너를 통과하는지 확인
checkov -d .
```

## 실제 배포 (AWS 계정 필요)

```bash
export AWS_PROFILE=study
terraform plan -var name_suffix=1234
terraform apply -var name_suffix=1234
terraform state list
#   module.log_bucket.aws_s3_bucket.this
#   module.data_bucket["raw"].aws_s3_bucket.this
#   module.data_bucket["processed"].aws_s3_bucket.this
#   ...
terraform destroy -var name_suffix=1234
```

## 학습 포인트

- **모듈은 provider 블록이 없다.** `versions.tf` 에 요구사항만 두고 루트가 넘겨준다.
- `default_tags` 로 프로바이더 레벨 태그를 걸면 모듈마다 태그를 넘기지 않아도 된다.
- `module.data_bucket["raw"]` 처럼 **for_each 모듈 주소**에 키가 들어간다.
- 로그 버킷은 `log_bucket = null` 로 자기 로깅을 끈다 → 스캐너가 이걸 지적하면 `#tfsec:ignore` + 사유.
- 모듈 안 `count = var.log_bucket == null ? 0 : 1` 은 "선택 기능 토글" 패턴.
- `depends_on` 이 두 곳 있다. 왜 참조만으로 순서가 잡히지 않는지 생각해 볼 것
  (lifecycle ↔ versioning, policy ↔ public_access_block 은 속성 참조 관계가 없다).

## 리팩터링 실습

1. `data_bucket` 의 for_each 키 `raw` 를 `landing` 으로 바꾸면 plan 이 어떻게 나오는지 확인 (삭제+생성).
2. 이를 막기 위해 `moved` 블록을 추가:
   ```hcl
   moved {
     from = module.data_bucket["raw"]
     to   = module.data_bucket["landing"]
   }
   ```
   다시 plan → 변경 없음.
