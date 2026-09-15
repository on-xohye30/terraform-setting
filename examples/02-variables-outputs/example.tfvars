# 복사해서 사용: cp example.tfvars prod.tfvars && terraform plan -var-file=prod.tfvars
# 시크릿(db_password)은 tfvars 에 적지 말고 환경변수로:  export TF_VAR_db_password='...'

project = "tfstudy"
env     = "prod"

allowed_cidrs = ["10.10.0.0/16", "192.168.100.0/24"]

servers = {
  web = { port = 443, public = true, size = "medium" }
  api = { port = 8080 }
  db  = { port = 5432, size = "large" }
}

extra_tags = {
  Owner      = "sec-team"
  CostCenter = "1234"
}
