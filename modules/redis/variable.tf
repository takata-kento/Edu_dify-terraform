variable "private_subnet_ids" {
  description = "value of private_subnet_ids"
  type        = list(string)
}

variable "security_group_ids" {
  description = "value of security_group_ids"
  type        = list(string)
}

variable "redis_password" {
  description = "value of redis_password"
  type        = string
}
