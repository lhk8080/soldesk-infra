output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "가비아 네임서버 설정에 입력할 NS 4개"
  value       = aws_route53_zone.this.name_servers
}
