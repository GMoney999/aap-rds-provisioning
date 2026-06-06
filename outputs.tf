output "rds_endpoint" {
  value = aws_db_instance.aap_postgres.endpoint
}
output "db_username" {
  value = var.db_username
}

