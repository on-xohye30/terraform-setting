provider "aws" {
  region = var.region

  # 자격증명은 코드에 두지 않는다. 환경변수 / 프로파일 / CI OIDC 역할로만 주입.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "web-db"
    }
  }
}
