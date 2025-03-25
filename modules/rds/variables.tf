variable "private_subnet_ids" {
  description = "The IDs of the private subnets in which the resources will be created."
  type        = list(string)
}

variable "security_group_ids" {
  description = "The IDs of the security groups in which the resources will be created."
  type        = list(string)
}

variable "db_master_password" {
  description = "The master password for the database."
  type        = string
}
