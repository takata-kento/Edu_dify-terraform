variable "alb_arn" {
  description = "The ARN of the ALB."
  type        = string
}

variable "default_target_group_arn" {
  description = "The ARN of the default target group."
  type        = string
}

variable "forwarding_settings" {
  description = "The settings to use for the target group."
  type = list(object({
    priority         = number
    path_patterns    = list(string)
    target_group_arn = string
  }))
}
