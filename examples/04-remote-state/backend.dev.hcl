# terraform init -backend-config=../backend.dev.hcl
# bootstrap 의 output "backend_config" 값으로 교체할 것
bucket         = "CHANGE-ME-tfstate-dev-1234"
region         = "ap-northeast-2"
dynamodb_table = "terraform-locks"
encrypt        = true
