data "aws_route53_zone" "main" {
  zone_id = var.zone_id
}

# Health checks per region - only create when we have valid ALB DNS names
resource "aws_route53_health_check" "regional" {
  for_each = { for k, v in var.alb_dns_names : k => v if v != "" && !startswith(v, "arn:") }

  fqdn              = each.value
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  request_interval  = var.health_check_interval
  failure_threshold = var.health_check_failure_threshold

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.key}-health-check"
    Environment = var.environment
    Region      = each.key
  })
}

# Latency-based routing records per region - only create when we have valid ALB DNS names
resource "aws_route53_record" "api_latency" {
  for_each = { for k, v in var.alb_dns_names : k => v if v != "" && !startswith(v, "arn:") && lookup(var.alb_zone_ids, k, "") != "" }

  zone_id = var.zone_id
  name    = "api-internal.${data.aws_route53_zone.main.name}"
  type    = "A"

  alias {
    name                   = each.value
    zone_id                = var.alb_zone_ids[each.key]
    evaluate_target_health = true
  }

  set_identifier = each.key

  latency_routing_policy {
    region = each.key
  }

  health_check_id = aws_route53_health_check.regional[each.key].id
}

# CloudWatch alarms for health checks
resource "aws_cloudwatch_metric_alarm" "health_check" {
  for_each = { for k, v in var.alb_dns_names : k => v if v != "" && !startswith(v, "arn:") }

  alarm_name          = "${var.environment}-${each.key}-health-check-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Health check alarm for ${each.key} region"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.regional[each.key].id
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.key}-health-check-alarm"
    Environment = var.environment
    Region      = each.key
  })
}
