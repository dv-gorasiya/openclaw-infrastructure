variable "environment" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "instance_id" {
  type = string
}

variable "asg_name" {
  type = string
}

variable "log_retention_days" {
  type = object({
    user_data   = number
    application = number
  })
}

variable "tags" {
  type = map(string)
}
