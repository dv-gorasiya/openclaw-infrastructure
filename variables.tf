variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "availability_zone" {
  description = "Availability zone for single-AZ deployment"
  type        = string
  default     = "eu-west-2a"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for OpenClaw"
  type        = string
  default     = "t3.micro"
}

variable "ebs_volume_size" {
  description = "Size of EBS data volume in GB"
  type        = number
  default     = 15
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 3
}

variable "backup_retention_weeks" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 14
}

variable "openclaw_ports" {
  description = "Ports used by OpenClaw services"
  type = object({
    gateway         = number
    browser_control = number
  })
  default = {
    gateway         = 18789
    browser_control = 18791
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type = object({
    user_data   = number
    application = number
  })
  default = {
    user_data   = 7
    application = 14
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
