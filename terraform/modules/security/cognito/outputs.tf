output "user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "The ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "client_id" {
  description = "The ID of the frontend app client"
  value       = aws_cognito_user_pool_client.frontend.id
}

output "backend_client_id" {
  description = "The ID of the backend app client"
  value       = aws_cognito_user_pool_client.backend.id
}

output "backend_client_secret" {
  description = "The secret of the backend app client"
  value       = aws_cognito_user_pool_client.backend.client_secret
  sensitive   = true
}

output "user_pool_endpoint" {
  description = "The endpoint URL of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.endpoint
}

output "user_pool_domain" {
  description = "The domain prefix of the Cognito User Pool"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "jwks_uri" {
  description = "The JWKS URI for token validation"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

output "issuer" {
  description = "The issuer URL for token validation"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
