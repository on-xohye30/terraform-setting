# cp example.tfvars prod.tfvars 후 값 교체. *.tfvars 는 커밋되지 않는다.
project        = "myapp"
environment    = "prod"
account_suffix = "1234"

vpc_id             = "vpc-0123456789abcdef0"
private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]

# 관리 접근 허용 대역. 0.0.0.0/0 은 validation 에서 거부된다.
admin_cidrs = ["10.10.0.0/16"]

instance_type            = "t3.small"
db_instance_class        = "db.t3.medium"
db_multi_az              = true
db_backup_retention_days = 14
