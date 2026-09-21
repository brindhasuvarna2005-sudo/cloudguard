output "bucket_name" {
  value = aws_s3_bucket.demo_bucket.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.demo_table.id
}

output "iam_role_name" {
  value = aws_iam_role.demo_role.id
}

output "security_group_id" {
  value = aws_security_group.demo_sg.id
}