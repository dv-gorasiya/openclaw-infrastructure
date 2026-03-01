variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "availability_zone" {
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
