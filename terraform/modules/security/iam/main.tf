data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# IAM role for S3 replication
resource "aws_iam_role" "s3_replication" {
  name = "${var.environment}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-s3-replication-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.environment}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = length(var.source_bucket_arns) > 0 ? var.source_bucket_arns : ["arn:${data.aws_partition.current.partition}:s3:::*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = length(var.source_bucket_arns) > 0 ? [for arn in var.source_bucket_arns : "${arn}/*"] : ["arn:${data.aws_partition.current.partition}:s3:::*/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = length(var.destination_bucket_arns) > 0 ? [for arn in var.destination_bucket_arns : "${arn}/*"] : ["arn:${data.aws_partition.current.partition}:s3:::*/*"]
      }
    ]
  })
}

# IAM role for MSK Replicator
resource "aws_iam_role" "msk_replicator" {
  name = "${var.environment}-msk-replicator-role"

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

  tags = merge(var.tags, {
    Name        = "${var.environment}-msk-replicator-role"
    Environment = var.environment
  })
}

resource "aws_iam_role_policy" "msk_replicator" {
  name = "${var.environment}-msk-replicator-policy"
  role = aws_iam_role.msk_replicator.id

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
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "*"
      }
    ]
  })
}
