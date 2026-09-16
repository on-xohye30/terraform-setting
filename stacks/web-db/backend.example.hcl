# cp backend.example.hcl backend.hcl 후 bootstrap 출력값으로 교체
bucket         = "myorg-tfstate-prod-1234"
region         = "ap-northeast-2"
dynamodb_table = "terraform-locks"
encrypt        = true
