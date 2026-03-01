variable "environment" {
  type = string
}

variable "ebs_volume_arn" {
  description = "ARN of the EBS data volume (for scoped IAM permissions)"
  type        = string
}

variable "enable_cloudtrail" {
  type = bool
}

variable "tags" {
  type = map(string)
}
