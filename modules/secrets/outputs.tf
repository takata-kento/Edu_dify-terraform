output "secret_arn" {
  description = "value of the secrets manager ARN"
  value       = aws_secretsmanager_secret.main.arn
}
