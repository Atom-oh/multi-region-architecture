locals {
  service_namespaces = [
    "core-services",
    "user-services",
    "fulfillment",
    "business-services",
    "platform"
  ]
}

# Default sampling rule - 5% of all traces
resource "aws_xray_sampling_rule" "default" {
  rule_name      = "${var.environment}-default"
  priority       = 1000
  reservoir_size = 1
  fixed_rate     = 0.05
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"
  version        = 1

  tags = merge(var.tags, {
    Name        = "${var.environment}-default-sampling"
    Environment = var.environment
  })
}

# Orders sampling rule - 100% of order traces
resource "aws_xray_sampling_rule" "orders" {
  rule_name      = "${var.environment}-orders"
  priority       = 100
  reservoir_size = 10
  fixed_rate     = 1.0
  url_path       = "/api/orders*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "order-service"
  resource_arn   = "*"
  version        = 1

  tags = merge(var.tags, {
    Name        = "${var.environment}-orders-sampling"
    Environment = var.environment
  })
}

# Errors sampling rule - 100% of 5XX errors
resource "aws_xray_sampling_rule" "errors" {
  rule_name      = "${var.environment}-errors"
  priority       = 50
  reservoir_size = 50
  fixed_rate     = 1.0
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"
  version        = 1

  attributes = {
    "http.status_code" = "5*"
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-errors-sampling"
    Environment = var.environment
  })
}

# X-Ray groups per service namespace
resource "aws_xray_group" "namespaces" {
  for_each = toset(local.service_namespaces)

  group_name        = "${var.environment}-${each.value}"
  filter_expression = "service(id(name: \"${each.value}\"))"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = true
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.value}-group"
    Environment = var.environment
    Namespace   = each.value
  })
}
