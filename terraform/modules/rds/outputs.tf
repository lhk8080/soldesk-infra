output "writer_endpoint" {
  value     = aws_db_instance.writer.address
  sensitive = true
}
output "reader_endpoint" {
  value     = aws_db_instance.reader.address
  sensitive = true
}
output "db_port" {
  value = aws_db_instance.writer.port
}
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
