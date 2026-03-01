variable "environment" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "ebs_volume_size" {
  type = number
}

variable "backup_retention_days" {
  type = number
}

variable "backup_retention_weeks" {
  type = number
}

variable "tags" {
  type = map(string)
}
