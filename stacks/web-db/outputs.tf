output "web_instance_id" {
  value = aws_instance.web.id
}

output "web_private_ip" {
  value = aws_instance.web.private_ip
}

output "db_endpoint" {
  value = aws_db_instance.db.endpoint
}

output "db_secret_arn" {
  description = "애플리케이션이 런타임에 조회할 시크릿의 위치. 값이 아니라 ARN 만 노출한다"
  value       = aws_secretsmanager_secret.db.arn
}

output "backup_bucket" {
  value = module.backups.id
}
