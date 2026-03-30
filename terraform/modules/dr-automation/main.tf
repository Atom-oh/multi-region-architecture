data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# SNS Topic for DR Alerts
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "dr_alerts" {
  name = "${var.environment}-dr-alerts"

  tags = merge(var.tags, {
    Name        = "${var.environment}-dr-alerts"
    Environment = var.environment
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# Lambda: DocumentDB Failover
# -----------------------------------------------------------------------------

data "archive_file" "docdb_failover" {
  type        = "zip"
  source_file = "${path.module}/lambda/docdb_failover.py"
  output_path = "${path.module}/lambda/docdb_failover.zip"
}

resource "aws_iam_role" "docdb_failover" {
  name = "${var.environment}-docdb-failover-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "docdb_failover" {
  name = "${var.environment}-docdb-failover-policy"
  role = aws_iam_role.docdb_failover.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:FailoverGlobalCluster",
          "rds:DescribeGlobalClusters",
          "rds:DescribeDBClusters"
        ]
        Resource = [
          "arn:aws:rds::${data.aws_caller_identity.current.account_id}:global-cluster:${var.docdb_global_cluster_id}",
          "arn:aws:rds:*:${data.aws_caller_identity.current.account_id}:cluster:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

resource "aws_lambda_function" "docdb_failover" {
  function_name = "${var.environment}-docdb-failover"
  description   = "Automated DocumentDB global cluster failover"
  runtime       = "python3.12"
  handler       = "docdb_failover.handler"
  role          = aws_iam_role.docdb_failover.arn
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.docdb_failover.output_path
  source_code_hash = data.archive_file.docdb_failover.output_base64sha256

  environment {
    variables = {
      GLOBAL_CLUSTER_ID    = var.docdb_global_cluster_id
      TARGET_CLUSTER_ID    = var.docdb_target_cluster_id
      SNS_TOPIC_ARN        = aws_sns_topic.dr_alerts.arn
      ENABLE_AUTO_FAILOVER = tostring(var.enable_auto_failover)
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-docdb-failover"
    Environment = var.environment
  })
}

resource "aws_lambda_permission" "docdb_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.docdb_failover.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_alarm.arn
}

# -----------------------------------------------------------------------------
# Lambda: ElastiCache Failover
# -----------------------------------------------------------------------------

data "archive_file" "elasticache_failover" {
  type        = "zip"
  source_file = "${path.module}/lambda/elasticache_failover.py"
  output_path = "${path.module}/lambda/elasticache_failover.zip"
}

resource "aws_iam_role" "elasticache_failover" {
  name = "${var.environment}-elasticache-failover-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "elasticache_failover" {
  name = "${var.environment}-elasticache-failover-policy"
  role = aws_iam_role.elasticache_failover.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticache:FailoverGlobalReplicationGroup",
          "elasticache:DescribeGlobalReplicationGroups",
          "elasticache:DescribeReplicationGroups"
        ]
        Resource = [
          "arn:aws:elasticache::${data.aws_caller_identity.current.account_id}:globalreplicationgroup:${var.elasticache_global_group_id}",
          "arn:aws:elasticache:*:${data.aws_caller_identity.current.account_id}:replicationgroup:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

resource "aws_lambda_function" "elasticache_failover" {
  function_name = "${var.environment}-elasticache-failover"
  description   = "Automated ElastiCache global replication group failover"
  runtime       = "python3.12"
  handler       = "elasticache_failover.handler"
  role          = aws_iam_role.elasticache_failover.arn
  timeout       = 300
  memory_size   = 256

  filename         = data.archive_file.elasticache_failover.output_path
  source_code_hash = data.archive_file.elasticache_failover.output_base64sha256

  environment {
    variables = {
      GLOBAL_REPLICATION_GROUP_ID = var.elasticache_global_group_id
      TARGET_REGION               = var.elasticache_target_region
      TARGET_REPLICATION_GROUP_ID = var.elasticache_target_group_id
      SNS_TOPIC_ARN               = aws_sns_topic.dr_alerts.arn
      ENABLE_AUTO_FAILOVER        = tostring(var.enable_auto_failover)
    }
  }

  tags = merge(var.tags, {
    Name        = "${var.environment}-elasticache-failover"
    Environment = var.environment
  })
}

resource "aws_lambda_permission" "elasticache_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.elasticache_failover.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.health_check_alarm.arn
}

# -----------------------------------------------------------------------------
# EventBridge Rule: Route53 Health Check Alarm
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "health_check_alarm" {
  name        = "${var.environment}-health-check-alarm-rule"
  description = "Triggers DR failover when Route53 health check goes to ALARM state"

  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
      alarmName = [{
        prefix = "${var.environment}-"
      }]
    }
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-health-check-alarm-rule"
    Environment = var.environment
  })
}

resource "aws_cloudwatch_event_target" "docdb_failover" {
  rule      = aws_cloudwatch_event_rule.health_check_alarm.name
  target_id = "docdb-failover"
  arn       = aws_lambda_function.docdb_failover.arn
}

resource "aws_cloudwatch_event_target" "elasticache_failover" {
  rule      = aws_cloudwatch_event_rule.health_check_alarm.name
  target_id = "elasticache-failover"
  arn       = aws_lambda_function.elasticache_failover.arn
}

resource "aws_cloudwatch_event_target" "sns_notification" {
  rule      = aws_cloudwatch_event_rule.health_check_alarm.name
  target_id = "sns-notification"
  arn       = aws_sns_topic.dr_alerts.arn

  input_transformer {
    input_paths = {
      alarmName = "$.detail.alarmName"
      state     = "$.detail.state.value"
      reason    = "$.detail.state.reason"
      time      = "$.time"
    }
    input_template = <<EOF
"DR ALERT: Health check alarm <alarmName> changed to <state> at <time>. Reason: <reason>. Auto-failover enabled: ${var.enable_auto_failover}"
EOF
  }
}

# SNS topic policy to allow EventBridge to publish
resource "aws_sns_topic_policy" "dr_alerts" {
  arn = aws_sns_topic.dr_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      },
      {
        Sid    = "AllowAccountPublish"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dr_alerts.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups for Lambda Functions
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "docdb_failover" {
  name              = "/aws/lambda/${aws_lambda_function.docdb_failover.function_name}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "elasticache_failover" {
  name              = "/aws/lambda/${aws_lambda_function.elasticache_failover.function_name}"
  retention_in_days = 30

  tags = var.tags
}
