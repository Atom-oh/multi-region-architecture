resource "aws_cloudwatch_log_group" "index_slow_logs" {
  name              = "/aws/opensearch/${var.environment}-opensearch-${var.region}/index-slow-logs"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "search_slow_logs" {
  name              = "/aws/opensearch/${var.environment}-opensearch-${var.region}/search-slow-logs"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "es_application_logs" {
  name              = "/aws/opensearch/${var.environment}-opensearch-${var.region}/es-application-logs"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${var.environment}-opensearch-logs-${var.region}"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "es.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:PutLogEventsBatch",
          "logs:CreateLogStream"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.index_slow_logs.arn}:*",
          "${aws_cloudwatch_log_group.search_slow_logs.arn}:*",
          "${aws_cloudwatch_log_group.es_application_logs.arn}:*"
        ]
      }
    ]
  })
}

locals {
  # OpenSearch domain name must be <= 28 chars
  # Use shortened region: us-east-1 -> use1, us-west-2 -> usw2
  short_region = replace(replace(var.region, "us-east-", "use"), "us-west-", "usw")
  domain_name  = "${var.environment}-os-${local.short_region}"
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.domain_name
  engine_version = "OpenSearch_2.17"

  cluster_config {
    dedicated_master_enabled = true
    dedicated_master_type    = var.master_instance_type
    dedicated_master_count   = var.master_instance_count

    instance_type  = var.data_instance_type
    instance_count = var.data_instance_count

    zone_awareness_enabled = true

    zone_awareness_config {
      availability_zone_count = 3
    }

    warm_enabled = var.enable_ultrawarm
    warm_type    = var.enable_ultrawarm ? var.warm_instance_type : null
    warm_count   = var.enable_ultrawarm ? var.warm_count : null
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.ebs_volume_size
    iops        = 3000
    throughput  = 250
  }

  vpc_options {
    subnet_ids         = var.data_subnet_ids
    security_group_ids = [var.security_group_id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = "admin"
      master_user_password = "Admin@SecurePass123!" # Should be replaced with Secrets Manager
    }
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.index_slow_logs.arn
    log_type                 = "INDEX_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.search_slow_logs.arn
    log_type                 = "SEARCH_SLOW_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.es_application_logs.arn
    log_type                 = "ES_APPLICATION_LOGS"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-opensearch-domain"
  })

  depends_on = [
    aws_cloudwatch_log_resource_policy.opensearch
  ]
}

resource "aws_iam_service_linked_role" "opensearch" {
  count            = var.create_service_linked_role ? 1 : 0
  aws_service_name = "opensearchservice.amazonaws.com"
}
