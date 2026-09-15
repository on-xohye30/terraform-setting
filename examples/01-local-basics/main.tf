# 01. 클라우드 계정 없이 Terraform 워크플로 익히기
#
# local 프로바이더로 파일을 "리소스"처럼 관리한다.
# init → plan → apply → (파일 수정 후) plan → destroy 를 돌려보며
# state 가 어떻게 코드 ↔ 실제(파일) 를 매핑하는지 관찰하는 것이 목적.

terraform {
  required_version = ">= 1.6"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# 프로바이더 설정 (local/random 은 설정할 인자가 없다)
provider "local" {}
provider "random" {}

locals {
  out_dir = "${path.module}/out"
}

# 1) 랜덤 값 — apply 할 때마다가 아니라 "처음 한 번"만 생성되고 state 에 저장된다
resource "random_pet" "name" {
  length    = 2
  separator = "-"
}

# 2) 파일 리소스 — content 가 바뀌면 plan 에서 재생성(-/+) 으로 표시된다
resource "local_file" "hello" {
  filename        = "${local.out_dir}/hello.txt"
  file_permission = "0644"
  content         = <<-EOT
    hello, terraform!
    generated name : ${random_pet.name.id}
    module path    : ${path.module}
  EOT
}

# 3) 암묵적 의존성 — hello 의 속성을 참조하므로 hello 가 먼저 생성된다
resource "local_file" "summary" {
  filename = "${local.out_dir}/summary.json"
  content = jsonencode({
    hello_file   = local_file.hello.filename
    hello_sha256 = local_file.hello.content_sha256
    pet          = random_pet.name.id
  })
}

# 4) 민감값 — state 에는 평문으로 저장된다는 점을 직접 확인해 볼 것
#    (apply 후 terraform.tfstate 를 열어 "token" 을 검색)
resource "random_password" "token" {
  length  = 24
  special = false
}

resource "local_sensitive_file" "secret" {
  filename        = "${local.out_dir}/secret.txt"
  file_permission = "0600"
  content         = random_password.token.result
}

output "pet_name" {
  value = random_pet.name.id
}

output "hello_path" {
  value = local_file.hello.filename
}

output "token" {
  value     = random_password.token.result
  sensitive = true # CLI 출력만 가려진다. terraform output -raw token 으로는 볼 수 있음
}
