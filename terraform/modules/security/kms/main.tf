data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# KMS keys for each service
resource "aws_kms_key" "keys" {
  for_each = toset(var.key_aliases)

  description             = "KMS key for ${each.value} - ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-${each.value}-key"
    Environment = var.environment
    Service     = each.value
  })
}

# KMS aliases for each key
resource "aws_kms_alias" "aliases" {
  for_each = toset(var.key_aliases)

  name          = "alias/${var.environment}-${each.value}"
  target_key_id = aws_kms_key.keys[each.value].key_id
}
