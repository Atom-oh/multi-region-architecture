output "secret_arns" {
  description = "Map of secret names to their ARNs"
  value = {
    for key, secret in aws_secretsmanager_secret.secrets : key => secret.arn
  }
}
