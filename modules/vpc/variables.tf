variable "cidr" { type = string }
variable "name" { type = string }
variable "public_subnets" { type = list(string) }
variable "azs" { type = list(string) }
variable "private_subnets"  { type = list(string) }
