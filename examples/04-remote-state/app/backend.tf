# 04-b. 원격 백엔드를 사용하는 프로젝트 쪽 설정
#
# backend 블록에는 변수/표현식을 쓸 수 없다. 환경별 값은 -backend-config 파일로 주입:
#   terraform init -backend-config=../backend.dev.hcl
#
# 이미 로컬 state 가 있는 상태에서 백엔드를 추가하면:
#   terraform init -migrate-state      # 로컬 → 원격 복사 (원본은 남음, 확인 후 삭제)

terraform {
  required_version = ">= 1.6"

  backend "s3" {
    # bucket / region / dynamodb_table / encrypt 는 backend.*.hcl 에서 주입
    key = "examples/04-remote-state/app/terraform.tfstate" # 프로젝트마다 고유 경로
    # use_lockfile = true   # Terraform 1.10+: DynamoDB 없이 S3 조건부 쓰기로 잠금
  }

  required_providers {
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# 백엔드 동작만 확인하는 최소 리소스
resource "random_pet" "app" {
  length = 2
}

output "app_name" {
  value = random_pet.app.id
}
