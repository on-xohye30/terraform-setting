# s3-secure-bucket

호출자가 어떤 옵션도 주지 않아도 다음이 보장되는 S3 버킷 모듈.

| 보장 | 구현 |
|---|---|
| 퍼블릭 접근 불가 | `aws_s3_bucket_public_access_block` 4개 옵션 모두 `true` |
| ACL 경로 차단 | `object_ownership = "BucketOwnerEnforced"` |
| 저장 시 암호화 | SSE-S3 기본, `kms_key_arn` 지정 시 SSE-KMS + Bucket Key |
| 전송 중 암호화 | `aws:SecureTransport = false` 요청을 Deny 하는 버킷 정책 |
| 복구 가능 | 버전 관리 기본 활성 |
| 비용·잔존 데이터 관리 | 이전 버전 만료, 미완료 멀티파트 정리 |
| 추적 | `log_bucket` 지정 시 액세스 로깅 |

## 사용

```hcl
module "logs" {
  source      = "../../modules/s3-secure-bucket"
  bucket_name = "myorg-prod-logs-1234"
}

module "data" {
  source      = "../../modules/s3-secure-bucket"
  bucket_name = "myorg-prod-data-1234"
  kms_key_arn = aws_kms_key.data.arn
  log_bucket  = module.logs.id
  tags        = { DataClass = "confidential" }
}
```

## 입력

| 이름 | 타입 | 기본값 | 설명 |
|---|---|---|---|
| `bucket_name` | `string` | 필수 | 버킷 이름. S3 명명 규칙을 `validation` 으로 검사 |
| `versioning` | `bool` | `true` | 버전 관리 |
| `kms_key_arn` | `string` | `null` | 지정 시 SSE-KMS, 미지정 시 SSE-S3 |
| `log_bucket` | `string` | `null` | 액세스 로그 대상 버킷. 로그 버킷 자신에게는 `null` |
| `expire_noncurrent_days` | `number` | `90` | 이전 버전 만료 일수 |
| `force_destroy` | `bool` | `false` | destroy 시 객체 강제 삭제. 프로덕션은 `false` 유지 |
| `tags` | `map(string)` | `{}` | 태그 |

## 출력

| 이름 | 설명 |
|---|---|
| `id` | 버킷 이름 |
| `arn` | 버킷 ARN |
| `domain_name` | 리전별 도메인 |

## 설계 메모

- 모듈은 `provider` 블록을 갖지 않는다. `versions.tf` 에 요구사항만 선언하고 루트가 주입한다.
- `aws_s3_bucket_policy` 는 `public_access_block` 이후에 적용되도록 `depends_on` 을 둔다. 정책이 먼저 붙으면 계정 설정에 따라 `BlockPublicPolicy` 오류가 날 수 있다.
- `lifecycle_configuration` 은 버전 관리가 켜진 뒤 적용돼야 `noncurrent_version_expiration` 이 유효하다.
- 스캐너 예외: 로그 버킷 자신의 로깅 미설정은 순환이므로 허용한다(`.checkov.yaml`, tfsec 인라인 주석).
