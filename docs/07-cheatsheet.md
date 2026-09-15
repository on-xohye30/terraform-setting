# 07. 치트시트

## 명령어

```bash
terraform init [-upgrade] [-backend-config=file.hcl] [-reconfigure|-migrate-state]
terraform fmt -recursive [-check -diff]
terraform validate
terraform plan [-out=tfplan] [-var k=v] [-var-file=f] [-target=addr] [-refresh-only] [-destroy]
terraform apply [tfplan | -auto-approve] [-replace=addr]
terraform destroy [-target=addr]
terraform show [-json] [tfplan]
terraform output [-json] [name]
terraform console
terraform graph | dot -Tsvg > g.svg
terraform providers [lock -platform=linux_amd64]
terraform state list|show|mv|rm|pull|push
terraform workspace list|new|select|delete
terraform import addr id            # 명령형 (선언형은 import 블록)
terraform force-unlock LOCK_ID
terraform login                     # Terraform Cloud
```

## 환경변수

| 변수 | 용도 |
|---|---|
| `TF_VAR_<name>` | 변수 주입 |
| `TF_LOG=TRACE\|DEBUG\|INFO` / `TF_LOG_PATH` | 디버그 로그 (민감정보 포함 주의) |
| `TF_INPUT=0` | 프롬프트 비활성 |
| `TF_CLI_ARGS_plan="-lock-timeout=5m"` | 서브커맨드 기본 옵션 |
| `TF_PLUGIN_CACHE_DIR` | 프로바이더 캐시 공유 |
| `TF_WORKSPACE` | 워크스페이스 강제 |

## 리소스 주소 문법

```
aws_instance.web
aws_instance.web[0]                 # count
aws_instance.web["blue"]            # for_each
module.vpc.aws_subnet.private[2]
module.app["prod"].module.db.aws_db_instance.this
```

## lifecycle

```hcl
lifecycle {
  create_before_destroy = true
  prevent_destroy       = true
  ignore_changes        = [tags["LastScan"], ami]
  replace_triggered_by  = [aws_launch_template.lt.latest_version]
  precondition {
    condition     = var.env != "prod" || var.multi_az
    error_message = "prod 는 multi_az 필수"
  }
  postcondition {
    condition     = self.encrypted
    error_message = "암호화 안 됨"
  }
}
```

## 버전 제약 연산자

| 표기 | 의미 |
|---|---|
| `= 1.6.0` / `1.6.0` | 정확히 |
| `>= 1.6` | 이상 |
| `~> 1.6` | `>= 1.6, < 2.0` |
| `~> 1.6.2` | `>= 1.6.2, < 1.7` |
| `>= 1.6, < 1.9` | 범위 |

## 자주 나는 오류 → 원인

| 메시지 | 원인 / 대응 |
|---|---|
| `Error acquiring the state lock` | 다른 실행 중이거나 죽은 잠금. 확인 후 `force-unlock` |
| `The "count" value depends on resource attributes that cannot be determined until apply` | count/for_each 키에 apply 후 결정 값 사용. 정적 값·변수로 교체 또는 `-target` 2단계 |
| `Provider produced inconsistent final plan` | 프로바이더 버그 / 버전 문제. 재실행 또는 버전 조정 |
| `Backend configuration changed` | `init -reconfigure`(상태 유지 안 함) 또는 `-migrate-state` |
| `Saved plan is stale` | plan 이후 state 변경. plan 다시 |
| `Inappropriate value for attribute` | 타입 불일치. `tolist/tomap` 또는 object 스키마 확인 |

## 파일 관례

```
main.tf  variables.tf  outputs.tf  versions.tf  providers.tf  locals.tf  data.tf
backend.tf  terraform.tfvars(커밋X)  example.tfvars(커밋O)  README.md
```
