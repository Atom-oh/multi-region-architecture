# Cognito User Pool for Multi-Region Mall Authentication
# Provides JWT-based authentication for API Gateway

resource "aws_cognito_user_pool" "main" {
  name = "${var.environment}-mall-users"

  # Use email as username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Account recovery via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Schema attributes
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  schema {
    name                     = "name"
    attribute_data_type      = "String"
    required                 = false
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  # Email configuration (use Cognito default for now)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  # Verification message
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Multi-Region Mall - Verify your email"
    email_message        = "Your verification code is {####}"
  }

  # MFA configuration (optional, off by default)
  mfa_configuration = "OFF"

  tags = merge(var.tags, {
    Name = "${var.environment}-mall-users"
  })
}

# User Pool Domain (for hosted UI and token endpoints)
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "multi-region-mall-${var.environment}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# App Client for Frontend (no client secret - public client)
resource "aws_cognito_user_pool_client" "frontend" {
  name         = "${var.environment}-mall-frontend"
  user_pool_id = aws_cognito_user_pool.main.id

  # No client secret for public clients (SPA/mobile)
  generate_secret = false

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Read/write attributes
  read_attributes  = ["email", "name", "email_verified"]
  write_attributes = ["email", "name"]
}

# App Client for Backend Services (with client secret - confidential client)
resource "aws_cognito_user_pool_client" "backend" {
  name         = "${var.environment}-mall-backend"
  user_pool_id = aws_cognito_user_pool.main.id

  # Client secret for confidential clients
  generate_secret = true

  # Auth flows for backend
  explicit_auth_flows = [
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Read/write attributes
  read_attributes  = ["email", "name", "email_verified"]
  write_attributes = ["email", "name"]
}
