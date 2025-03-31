resource "aws_lb_listener" "main" {
  load_balancer_arn = var.alb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = var.default_target_group_arn
  }
}

resource "aws_lb_listener_rule" "main" {
  count        = length(var.forwarding_settings)
  listener_arn = aws_lb_listener.main.arn
  priority     = var.forwarding_settings[count.index].priority

  condition {
    path_pattern {
      values = var.forwarding_settings[count.index].path_patterns
    }
  }

  action {
    type             = "forward"
    target_group_arn = var.forwarding_settings[count.index].target_group_arn
  }
}
