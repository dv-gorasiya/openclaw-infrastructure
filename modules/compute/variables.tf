variable "environment" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_sg_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "ebs_volume_id" {
  type = string
}

variable "secrets_manager_arn" {
  type = string
}

variable "secrets_manager_name" {
  type = string
}

variable "openclaw_ports" {
  type = object({
    gateway         = number
    browser_control = number
  })
}

variable "tags" {
  type = map(string)
}
