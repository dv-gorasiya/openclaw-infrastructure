variable "environment" {
  type = string
}

variable "enable_cloudtrail" {
  type = bool
}

variable "tags" {
  type = map(string)
}
