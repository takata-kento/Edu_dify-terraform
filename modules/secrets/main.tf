resource "aws_secretsmanager_secret" "main" {
  name = var.name
}

resource "aws_secretsmanager_secret_version" "main" {
  secret_id = aws_secretsmanager_secret.main.id
  # secret_string = var.secret_value
  secret_string = jsonencode(var.secret_value)
}
