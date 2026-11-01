output "application_instance_id" {
  value = aws_instance.application.id
}

output "application_public_ip" {
  value = aws_eip.application.public_ip
}

output "application_ingress_ip" {
  description = "Stable Elastic IP for public Courier HTTPS ingress and the courier.io.vn A record."
  value       = aws_eip.application.public_ip
}

output "data_instance_id" {
  value = aws_instance.data.id
}

output "data_private_ip" {
  value = aws_instance.data.private_ip
}

output "files_bucket_name" {
  value = aws_s3_bucket.files.bucket
}

output "backups_bucket_name" {
  value = aws_s3_bucket.backups.bucket
}

output "github_ecr_publisher_role_arn" {
  value = aws_iam_role.github_ecr_publisher.arn
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}
