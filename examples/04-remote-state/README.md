# 04. remote-state — S3 백엔드 + DynamoDB 잠금

```
04-remote-state/
├── bootstrap/        # state 버킷 + 잠금 테이블을 만드는 1회성 프로젝트 (로컬 state)
├── app/              # 그 백엔드를 사용하는 일반 프로젝트
└── backend.dev.hcl   # 환경별 backend 설정 (init 때 주입)
```

## 순서

```bash
# 1) 부트스트랩 (AWS 계정 필요)
cd bootstrap
terraform init
terraform apply -var state_bucket_name=tfstudy-tfstate-dev-1234
terraform output -raw backend_config       # → ../backend.dev.hcl 에 반영

# 2) 앱 프로젝트에서 원격 백엔드 사용
cd ../app
terraform init -backend-config=../backend.dev.hcl
terraform apply -auto-approve
ls            # terraform.tfstate 가 로컬에 생기지 않음
aws s3 ls s3://tfstudy-tfstate-dev-1234/examples/04-remote-state/app/
```

## 잠금 체험

터미널 두 개에서 `app/` 에 동시에 `terraform apply` (첫 번째는 확인 프롬프트에서 대기).
두 번째는 다음 오류로 막힌다:

```
Error: Error acquiring the state lock
Lock Info:
  ID:        xxxxxxxx-...
  Who:       user@host
  Operation: OperationTypeApply
```

첫 번째를 취소하면 잠금이 풀린다. 프로세스가 죽어 잠금이 남았을 때만 `terraform force-unlock <ID>`.

## 학습 포인트

- **닭과 달걀**: state 버킷을 만드는 코드는 원격 백엔드를 쓸 수 없다. bootstrap 의 로컬 state 는 별도 보관하거나
  버킷 생성 후 `-migrate-state` 로 자기 자신에게 옮긴다.
- backend 블록엔 변수 불가 → `-backend-config=파일`.
- `key` 는 프로젝트별 고유 경로. 같은 key 를 두 프로젝트가 쓰면 서로 state 를 덮어쓴다.
- state 버킷 요건: 버전 관리(복구), 암호화, 퍼블릭 차단, 최소권한 IAM, `prevent_destroy`.
- 1.10+ 는 `use_lockfile = true` 로 DynamoDB 없이 잠금 가능. 기존 프로젝트는 DynamoDB 병행 후 전환.

## 정리

```bash
cd app && terraform destroy -auto-approve
cd ../bootstrap && terraform destroy -var state_bucket_name=...   # 버킷에 state 객체가 남아 있으면 먼저 비워야 함
```
