terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 의도적으로 backend 를 두지 않는다.
  # 이 디렉터리는 원격 state 저장소 자체를 만들기 때문에 로컬 state 로 1회 실행하고,
  # 생성된 terraform.tfstate 는 생성한 버킷으로 `init -migrate-state` 하거나 안전한 곳에 보관한다.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Component = "tfstate-bootstrap"
    }
  }
}
