output "sql_arn_id" {
  value = aws_db_instance.sql_server.arn
}
output "sql_endpoint" {
  value = aws_db_instance.sql_server.address
}