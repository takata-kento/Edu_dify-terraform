resource "aws_cloudwatch_log_group" "main" {
  count             = length(var.container_definitions)
  name              = "/dify/container-logs/${var.container_definitions[count.index].name}"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "main" {
  family                   = var.family_name
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048

  dynamic "volume" {
    for_each = var.volume_name != null ? [var.volume_name] : []

    content {
      name = volume.value
    }
  }

  container_definitions = jsonencode([
    for i, value in var.container_definitions : {
      name         = value.name
      image        = value.image
      essential    = value.essential
      portMappings = value.portMappings
      environment  = value.environment
      secrets      = value.secrets
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main[i].name
          "awslogs-region"        = "ap-northeast-1"
          "awslogs-stream-prefix" = value.name
        }
      }
      healthCheck = value.healthCheck
      cpu         = value.cpu
      mountPoints = value.mountPoints
      entryPoint  = value.entryPoint
      command     = value.command
      volumesFrom = value.volumesFrom
      mountPoints = value.mountPoints
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "main" {
  name            = var.family_name
  cluster         = var.ecs_cluster_name
  desired_count   = var.desired_count
  task_definition = aws_ecs_task_definition.main.arn
  propagate_tags  = "SERVICE"
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = var.security_group_ids
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer_setting != null ? [0] : []

    content {
      target_group_arn = var.load_balancer_setting.target_group_arn
      container_name   = var.family_name
      container_port   = var.load_balancer_setting.container_port
    }
  }
}
