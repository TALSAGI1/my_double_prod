variable "name" {
  type = string
}

variable "description" {
  type    = string
  default = "Allow inbound traffic"
}

variable "vpc_id" {
  type = string
}

variable "tags" {
  description = "Tags to apply to the security group"
  type        = map(string)
  default     = {}
}
