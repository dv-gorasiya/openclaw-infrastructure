output "secrets_manager_name" {
  value = aws_secretsmanager_secret.openclaw.name
}

output "secrets_manager_arn" {
  value = aws_secretsmanager_secret.openclaw.arn
}

output "gateway_token" {
  value     = random_password.gateway_token.result
  sensitive = true
}

output "instance_role_name" {
  value = aws_iam_role.instance.name
}

output "instance_profile_name" {
  value = aws_iam_instance_profile.instance.name
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.instance.arn
}

output "cloudtrail_name" {
  value = var.enable_cloudtrail ? aws_cloudtrail.main[0].name : null
}
