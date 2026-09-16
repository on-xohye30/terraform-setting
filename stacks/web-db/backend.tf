# 원격 state. bucket / region / dynamodb_table / encrypt 는 backend.hcl 로 주입한다:
#   terraform init -backend-config=backend.hcl
# backend.hcl 은 bootstrap 의 `terraform output -raw backend_config` 로 생성하며 커밋하지 않는다.
terraform {
  backend "s3" {
    key = "stacks/web-db/terraform.tfstate"
  }
}
