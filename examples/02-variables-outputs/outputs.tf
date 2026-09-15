output "name_prefix" {
  description = "리소스 이름 접두어"
  value       = local.name_prefix
}

output "server_fqdns" {
  description = "서버 이름 → FQDN"
  value       = { for name, s in local.servers : name => s.fqdn }
}

output "public_servers" {
  description = "외부 공개 서버 목록"
  value       = local.public_servers
}

output "config_files" {
  description = "생성된 설정 파일 경로"
  value       = [for f in local_file.server_config : f.filename]
}

output "db_password" {
  description = "DB 비밀번호 (마스킹). 실제 값은 terraform output -raw db_password"
  value       = local.db_password
  sensitive   = true
}
