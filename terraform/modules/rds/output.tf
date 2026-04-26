output "endpoint" {
  value = aws_db_instance.this.endpoint
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "db_access_sg_id" {
  value = aws_security_group.db_access.id
}