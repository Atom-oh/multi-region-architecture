# ─────────────────────────────────────────────────────────────────────────────
# Private backups bucket — scripts/backup-restore/ archives land here.
#
# Deliberately NOT the static-assets bucket: that bucket is a CloudFront
# origin whose default cache behavior serves any non-/api/*,/static/* path
# publicly, so a DB dump under backups/ there would be downloadable at
# https://mall.<domain>/backups/<archive>. This bucket has no CloudFront
# origin and blocks all public access.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Account ID suffix: S3 bucket names are global, so environment+region alone is
  # squattable — anyone can take "production-mall-backups-ap-northeast-2" and
  # this layer's create then fails (or worse, in a fresh account, silently
  # targets someone else's naming space).
  backups_bucket_name = "${var.environment}-mall-backups-${var.region}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "backups" {
  bucket = local.backups_bucket_name

  tags = merge(var.tags, {
    Name = local.backups_bucket_name
  })
}

# Backups are the last copy of data by definition — a bad overwrite (a truncated
# archive uploaded over a good one at the same key) must be recoverable.
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.backups.arn,
        "${aws_s3_bucket.backups.arn}/*"
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.kms.key_arns["s3"]
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = 90
    }

    # With versioning on, expiration only adds delete markers — noncurrent
    # versions would accumulate forever and keep paying KMS+storage.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

output "backups_bucket_name" {
  description = "Private backups bucket for scripts/backup-restore/ archives"
  value       = aws_s3_bucket.backups.bucket
}
