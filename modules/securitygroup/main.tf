resource "aws_security_group" "main" {
  name        = var.name
  description = var.description
  vpc_id      = var.vpc_id
  tags        = { Name = "dify-api" }
}

resource "aws_security_group_rule" "main" {
  count = length(var.rules)

  description       = var.rules[count.index].description
  type              = var.rules[count.index].type
  from_port         = var.rules[count.index].from_port
  to_port           = var.rules[count.index].to_port
  protocol          = var.rules[count.index].protocol
  cidr_blocks       = var.rules[count.index].cidr_blocks
  source_security_group_id = var.rules[count.index].source_security_group_id
  security_group_id = aws_security_group.main.id
}
