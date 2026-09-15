# 02. variables-outputs — 변수 검증, locals, 표현식, for_each

## 실행

```bash
terraform init
terraform apply -auto-approve
cat out/web.conf
terraform output
terraform output -json server_fqdns
```

## 실험

1. **validation 걸리게 하기**
   ```bash
   terraform plan -var='env=qa'                          # env 검증 실패
   terraform plan -var='allowed_cidrs=["0.0.0.0/0"]'     # 전체 개방 차단
   terraform plan -var='project=Bad_Name'                # 정규식 실패
   ```

2. **precondition** — prod 에서 monitor=false 서버를 넣어보기
   ```bash
   terraform plan -var='env=prod' \
     -var='servers={ web = { port = 443, monitor = false } }'
   ```

3. **값 주입 우선순위**
   ```bash
   export TF_VAR_env=stage
   terraform plan                          # stage
   terraform plan -var-file=example.tfvars # prod (파일이 환경변수보다 우선)
   terraform plan -var-file=example.tfvars -var=env=dev   # dev (-var 가 최우선)
   unset TF_VAR_env
   ```

4. **for_each 의 안정성** — `servers` 에서 `api` 만 지우고 plan
   → `local_file.server_config["api"]` 하나만 `-`. 나머지는 그대로.
   (같은 걸 `count` + list 로 짰다면 뒤 요소가 밀려 재생성됐을 것)

5. **sensitive 전파**
   `outputs.tf` 의 `db_password` 에서 `sensitive = true` 를 지우면
   "Output refers to sensitive values" 오류. sensitive 는 참조를 따라 전파된다.

6. **시크릿 주입**
   ```bash
   TF_VAR_db_password='from-env' terraform apply -auto-approve
   cat out/db.env
   ```
   `random_password.db` 는 count=0 이 되어 삭제된다 → count 토글 패턴.

## 정리

```bash
terraform destroy -auto-approve
```
