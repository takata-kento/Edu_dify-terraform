variable "name" {
  description = "The name of the secret."
  type        = string
}

variable "secret_value" {
  description = "The value of the secret."
  # type        = string
  type        = map(string)
}
