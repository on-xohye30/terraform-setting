# 01. local-basics — 워크플로와 state 관찰

클라우드 계정 없이 `local`, `random` 프로바이더만으로 Terraform 의 전체 사이클을 돌려본다.

## 실행

```bash
terraform init
terraform validate
terraform plan
terraform apply -auto-approve

cat out/hello.txt
cat out/summary.json
terraform output
terraform output -raw token        # sensitive 도 -raw 로는 조회됨
```

## 관찰 포인트

1. **state 열어보기**
   ```bash
   terraform state list
   terraform state show random_password.token     # 평문 노출
   grep -n '"result"' terraform.tfstate           # state 파일 안에도 평문
   ```
   → `sensitive = true` 는 화면 마스킹일 뿐, state 보호는 별개 문제라는 것을 확인.

2. **드리프트 만들기**
   ```bash
   echo "tampered" >> out/hello.txt
   terraform plan          # content 차이를 감지 → 재생성 계획
   rm out/summary.json
   terraform plan          # 없어진 리소스 → + 생성 계획
   terraform apply -auto-approve
   ```

3. **코드 변경 → 재생성**
   `main.tf` 의 `hello` content 에 한 줄을 추가하고 `plan` → `-/+` (local_file 은 content 변경 시 교체) 를 확인.
   `summary` 도 `hello` 의 sha256 을 참조하므로 연쇄적으로 바뀐다 → 의존성 그래프 체감.

4. **random 리소스는 다시 만들지 않는다**
   `apply` 를 여러 번 해도 `random_pet.name` 은 state 에 있는 값을 유지한다.
   강제로 바꾸려면 `terraform apply -replace=random_pet.name`.

5. **정리**
   ```bash
   terraform destroy -auto-approve
   ls out/      # 비어 있음
   ```

## 생성 파일

| 파일 | 커밋 | 비고 |
|---|---|---|
| `.terraform/` | ✗ | 프로바이더 바이너리 |
| `.terraform.lock.hcl` | 실습이라 ✗ | 팀 프로젝트는 ✓ |
| `terraform.tfstate` | **✗** | 랜덤 토큰이 평문으로 들어있다 |
| `out/` | ✗ | 리소스 산출물 |
