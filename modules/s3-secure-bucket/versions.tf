# 모듈은 provider 블록을 갖지 않는다. 필요한 프로바이더 "요구사항" 만 선언한다.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
