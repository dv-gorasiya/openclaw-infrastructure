resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.ebs_volume_size
  type              = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125

  tags = merge(var.tags, {
    Name      = "openclaw-data-volume"
    Backup    = "true"
    MountPath = "/mnt/openclaw-data"
  })
}

resource "aws_backup_vault" "main" {
  name = "openclaw-backup-vault"
  tags = merge(var.tags, { Name = "openclaw-backup-vault" })
}

resource "aws_iam_role" "backup" {
  name = "openclaw-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
    }]
  })

  tags = merge(var.tags, { Name = "openclaw-backup-role" })
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "backup_restore" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "main" {
  name = "openclaw-backup-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 2 * * ? *)"
    lifecycle { delete_after = var.backup_retention_days }
    recovery_point_tags = merge(var.tags, { BackupType = "Daily" })
  }

  rule {
    rule_name         = "weekly"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 3 ? * SUN *)"
    lifecycle { delete_after = var.backup_retention_weeks }
    recovery_point_tags = merge(var.tags, { BackupType = "Weekly" })
  }

  tags = merge(var.tags, { Name = "openclaw-backup-plan" })
}

resource "aws_backup_selection" "main" {
  name         = "openclaw-backup-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "true"
  }
}
