resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "uploads" {
  bucket = "${var.project_name}-uploads-${var.environment}-${random_id.suffix.hex}"

  lifecycle {
    precondition {
      condition     = length("${var.project_name}-uploads-${var.environment}-${random_id.suffix.hex}") <= 63
      error_message = "Generated S3 bucket name '${var.project_name}-uploads-${var.environment}-${random_id.suffix.hex}' is ${length("${var.project_name}-uploads-${var.environment}-${random_id.suffix.hex}")} characters, exceeding the 63-character S3 limit. The fixed overhead (-uploads-, two separating hyphens, and the 8-character hex suffix) uses 18 characters; the remaining 45 must be shared between name (${length(var.project_name)} chars) and environment (${length(var.environment)} chars). Reduce one or both."
    }
  }

  tags = {
    Name        = "${var.project_name}-uploads"
    Project     = var.project_name
    Owner       = var.owner
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  depends_on = [aws_s3_bucket.uploads]

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled       = false
    blocked_encryption_types = ["SSE-C"]
  }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

