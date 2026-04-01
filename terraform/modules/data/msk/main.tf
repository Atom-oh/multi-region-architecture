locals {
  topics = {
    "orders.created"        = { partitions = 12 }
    "orders.confirmed"      = { partitions = 12 }
    "orders.cancelled"      = { partitions = 6 }
    "payments.completed"    = { partitions = 12 }
    "payments.failed"       = { partitions = 6 }
    "catalog.updated"       = { partitions = 12 }
    "catalog.price-changed" = { partitions = 6 }
    "inventory.reserved"    = { partitions = 24 }
    "inventory.released"    = { partitions = 12 }
    "user.registered"       = { partitions = 6 }
    "user.activity"         = { partitions = 24 }
    "reviews.created"       = { partitions = 6 }
  }
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.environment}-msk-${var.region}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_msk_configuration" "this" {
  name           = "${var.environment}-msk-config-${var.region}"
  kafka_versions = [var.kafka_version]

  server_properties = <<PROPERTIES
auto.create.topics.enable=false
default.replication.factor=${var.default_replication_factor}
min.insync.replicas=${var.min_insync_replicas}
num.partitions=6
log.retention.hours=168
PROPERTIES

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_msk_cluster" "this" {
  cluster_name           = "${var.environment}-msk-${var.region}"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.data_subnet_ids
    security_groups = [var.security_group_id]

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.kms_key_arn

    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      scram = true
    }
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-msk-cluster"
  })
}

# IAM role for MSK Replicator
resource "aws_iam_role" "msk_replicator" {
  count = var.enable_replicator ? 1 : 0

  name = "${var.environment}-msk-replicator-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "kafka.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "msk_replicator" {
  count = var.enable_replicator ? 1 : 0

  name = "${var.environment}-msk-replicator-policy"
  role = aws_iam_role.msk_replicator[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = [
          var.source_cluster_arn,
          var.target_cluster_arn,
          "${var.source_cluster_arn}/*",
          "${var.target_cluster_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_msk_replicator" "this" {
  count = var.enable_replicator ? 1 : 0

  replicator_name = "${var.environment}-msk-replicator-${var.region}"

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = var.source_cluster_arn
    }

    vpc_config {
      subnet_ids          = var.data_subnet_ids
      security_groups_ids = [var.security_group_id]
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = var.target_cluster_arn
    }

    vpc_config {
      subnet_ids          = var.data_subnet_ids
      security_groups_ids = [var.security_group_id]
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = var.source_cluster_arn
    target_kafka_cluster_arn = var.target_cluster_arn
    target_compression_type  = "GZIP"

    topic_replication {
      topics_to_replicate = var.replicator_topics

      copy_access_control_lists_for_topics = true
      copy_topic_configurations            = true
      detect_and_copy_new_topics           = true
    }

    consumer_group_replication {
      consumer_groups_to_replicate        = [".*"]
      synchronise_consumer_group_offsets  = true
      detect_and_copy_new_consumer_groups = true
    }
  }

  service_execution_role_arn = aws_iam_role.msk_replicator[0].arn

  tags = merge(var.tags, {
    Name = "${var.environment}-msk-replicator"
  })
}
