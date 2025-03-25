variable "identifiers" {
  description = "The identifiers of the services that can assume the role."
  type        = list(string)
}

variable "policy_map" {
  description = "The information of the policy."
  type = list(object({
    policy_name = string
    actions     = list(string)
    resources   = list(string)
  }))
}

variable "role_name" {
  description = "The name of the role."
  type        = string
}

variable "role_description" {
  description = "The description of the role."
  type        = string
}
