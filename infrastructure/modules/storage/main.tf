# ── modules/storage ──────────────────────────────────────────────────────────
# Required resources (Task B1). Only these belong in this module:
#
#   aws_s3_bucket
#   aws_s3_bucket_public_access_block
#   aws_s3_bucket_versioning
#   aws_s3_bucket_server_side_encryption_configuration
#   aws_s3_object  x4                 the raw/ processed/ features/ artifacts/ prefixes
#   aws_s3_bucket_lifecycle_configuration   Lab 2; skipped when enable_lifecycle_rules = false
#
# ONE bucket with four prefixes, not four buckets. Later labs derive the name
# as ${project}-${environment}-data-${account_id}, so keep that shape.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "data" {
  bucket = "${var.project}-${var.environment}-data-${data.aws_caller_identity.current.account_id}"

  # Versioning means a plain destroy fails with BucketNotEmpty. True in dev
  # only: right for synthetic, regenerable lab data, wrong for real customer
  # records, because it deletes every version without asking.
  force_destroy = var.force_destroy

  tags = {
    Name = "${var.project}-${var.environment}-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "prefixes" {
  for_each = toset(var.prefixes)

  bucket = aws_s3_bucket.data.id
  key    = each.value
}

# ── Lab 2: lifecycle rules ───────────────────────────────────────────────────
# Versioning (Lab 1) keeps every overwritten object forever unless something
# expires the noncurrent versions. The Glue jobs overwrite processed/ and
# features/ on every run, so without these rules storage only ever grows.
#
# datacapture/ has no writer until Lab 5 (endpoint data capture). The rule is
# set now so retention exists before the writer does: capture writes one object
# per interval for as long as an endpoint is live, and nothing else prunes it.

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  count  = var.enable_lifecycle_rules ? 1 : 0
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "expire-raw-data"
    status = "Enabled"
    filter {
      prefix = "raw/"
    }
    expiration {
      days = 90
    }
  }

  rule {
    id     = "expire-raw-versions"
    status = "Enabled"
    filter {
      prefix = "raw/"
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-processed-versions"
    status = "Enabled"
    filter {
      prefix = "processed/"
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "expire-feature-versions"
    status = "Enabled"
    filter {
      prefix = "features/"
    }
    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }

  rule {
    id     = "expire-datacapture"
    status = "Enabled"
    filter {
      prefix = "datacapture/"
    }
    expiration {
      days = 7
    }
  }

  # Noncurrent-version rules are meaningless until versioning is on, and S3
  # rejects a lifecycle config that races the versioning call.
  depends_on = [aws_s3_bucket_versioning.data]
}
