output "ebs_volume_id" {
  value = aws_ebs_volume.data.id
}

output "ebs_volume_arn" {
  value = aws_ebs_volume.data.arn
}

output "backup_vault_name" {
  value = aws_backup_vault.main.name
}

output "backup_plan_id" {
  value = aws_backup_plan.main.id
}
