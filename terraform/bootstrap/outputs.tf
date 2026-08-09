output "state_bucket" {
  description = "S3 bucket holding the main stack's Terraform state."
  value       = aws_s3_bucket.state.id
}

output "backup_bucket" {
  description = "S3 bucket holding database dumps. Outlives terraform destroy."
  value       = aws_s3_bucket.backups.id
}

output "backend_config" {
  description = "Paste into terraform/main/backend.tf."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "main/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
