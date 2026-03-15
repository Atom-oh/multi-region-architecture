locals {
  namespaces = [
    "core-services",
    "user-services",
    "fulfillment",
    "business-services",
    "platform"
  ]
}

# CloudWatch Log Groups per namespace
resource "aws_cloudwatch_log_group" "eks_namespaces" {
  for_each = toset(local.namespaces)

  name              = "/eks/${var.eks_cluster_name}/${each.value}"
  retention_in_days = 90

  tags = merge(var.tags, {
    Name        = "/eks/${var.eks_cluster_name}/${each.value}"
    Environment = var.environment
    Namespace   = each.value
  })
}

# CloudWatch Alarm: High Error Rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "High 5XX error rate detected (>1% for 5 minutes)"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-high-error-rate"
    Environment = var.environment
  })
}

# CloudWatch Alarm: High Latency
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.environment}-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "High latency detected (>2s for 5 minutes)"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-high-latency"
    Environment = var.environment
  })
}

# CloudWatch Alarm: Aurora Replication Lag
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  alarm_name          = "${var.environment}-aurora-replication-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "Aurora replication lag >1000ms"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-aurora-replication-lag"
    Environment = var.environment
  })
}

# CloudWatch Alarm: Kafka Under Replicated Partitions
resource "aws_cloudwatch_metric_alarm" "kafka_under_replicated" {
  alarm_name          = "${var.environment}-msk-under-replicated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "MSK has under-replicated partitions"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name        = "${var.environment}-msk-under-replicated"
    Environment = var.environment
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-platform-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ALB Response Time"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "5XX Error Rate"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", { stat = "Sum", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Aurora Replication Lag"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["AWS/RDS", "AuroraReplicaLag", { stat = "Average", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "MSK Bytes In/Out"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["AWS/Kafka", "BytesInPerSec", { stat = "Average", period = 60 }],
            ["AWS/Kafka", "BytesOutPerSec", { stat = "Average", period = 60 }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "EKS Node CPU Utilization"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", var.eks_cluster_name, { stat = "Average", period = 60 }]
          ]
        }
      }
    ]
  })
}
