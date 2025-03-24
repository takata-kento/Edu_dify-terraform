variable "vpc_id" {
  description = "value of the VPC ID"
  type        = string
}

variable "name" {
  description = "The name of the security group."
  type        = string
}

variable "description" {
  description = "The description of the security group."
  type        = string
}

variable "rules" {
  description = "The list of security group rules to create."
  type = list(object({
    description = string
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = optional(list(string))
    source_security_group_id = optional(string)
  }))
}
