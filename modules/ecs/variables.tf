variable "family_name" {
  description = "The name of the ECS task definition family."
  type        = string
}

variable "execution_role_arn" {
  description = "The ARN of the IAM role to use for the ECS task execution role."
  type        = string
}

variable "task_role_arn" {
  description = "The ARN of the IAM role to use for the ECS task role."
  type        = string
}

variable "volume_name" {
  description = "The name of the volume to attach to the ECS task definition."
  type        = string
  default     = null
}

variable "container_definitions" {
  description = "The container definition for the ECS task definition."
  type = list(object({
    name      = string
    image     = string
    essential = bool
    portMappings = optional(list(object({
      hostPort      = number
      protocol      = string
      containerPort = number
    })))
    environment = optional(list(object({
      name  = string
      value = string
    })))
    secrets = optional(list(object({
      name      = string
      valueFrom = string
    })))
    healthCheck = optional(object({
      command     = list(string)
      interval    = number
      timeout     = number
      retries     = number
      startPeriod = number
    }))
    mountPoints = optional(list(object({
        sourceVolume  = string
        containerPath = string
    })))
    entryPoint = optional(list(string))
    command    = optional(list(string))
    cpu         = number
    volumesFrom = optional(list(string))
  }))
}

variable "ecs_cluster_name" {
  description = "The name of the ECS cluster in which the service will be created."
  type        = string
}

variable "desired_count" {
  description = "The desired number of tasks to run in the ECS service."
  type        = number
}

variable "private_subnet_ids" {
  description = "The IDs of the private subnets in which the ECS service will be created."
  type        = list(string)
}

variable "security_group_ids" {
  description = "The IDs of the security groups to associate with the ECS service."
  type        = list(string)
}

variable "load_balancer_setting" {
  description = "The settings for the load balancer to associate with the ECS service."
  type = object({
    target_group_arn = string
    container_port   = number
  })
  default = null
}
