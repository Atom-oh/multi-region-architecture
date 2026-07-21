# ─────────────────────────────────────────────────────────────────────────────
# Private backups bucket — scripts/backup-restore/ archives land here.
#
# Deliberately NOT the static-assets bucket: that bucket is a CloudFront
# origin whose default cache behavior serves any non-/api/*,/static/* path
# publicly, so a DB dump under backups/ there would be downloadable at
# https://mall.<domain>/backups/<archive>. This bucket has no CloudFront
# origin and blocks all public access.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "backups" {
  bucket = "${var.environment}-mall-backups-${var.region}"

  tags = merge(var.tags, {
    Name = "${var.environment}-mall-backups-${var.region}"
  })
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
  }
}

output "backups_bucket_name" {
  description = "Private backups bucket for scripts/backup-restore/ archives"
  value       = aws_s3_bucket.backups.bucket
}
