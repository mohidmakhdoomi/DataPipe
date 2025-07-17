# S3 Buckets for Data Lake
resource "aws_s3_bucket" "data_lake_raw" {
  bucket = "${local.name_prefix}-data-lake-raw-${random_string.bucket_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-lake-raw"
    Tier = "raw"
  })
}

resource "aws_s3_bucket" "data_lake_processed" {
  bucket = "${local.name_prefix}-data-lake-processed-${random_string.bucket_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-lake-processed"
    Tier = "processed"
  })
}

resource "aws_s3_bucket" "data_lake_curated" {
  bucket = "${local.name_prefix}-data-lake-curated-${random_string.bucket_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-lake-curated"
    Tier = "curated"
  })
}

resource "aws_s3_bucket" "airflow_logs" {
  bucket = "${local.name_prefix}-airflow-logs-${random_string.bucket_suffix.result}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-airflow-logs"
    Purpose = "airflow-logs"
  })
}

# Random string for unique bucket names
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "data_lake_raw" {
  bucket = aws_s3_bucket.data_lake_raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "data_lake_processed" {
  bucket = aws_s3_bucket.data_lake_processed.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "data_lake_curated" {
  bucket = aws_s3_bucket.data_lake_curated.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_raw" {
  bucket = aws_s3_bucket.data_lake_raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_processed" {
  bucket = aws_s3_bucket.data_lake_processed.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_curated" {
  bucket = aws_s3_bucket.data_lake_curated.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "airflow_logs" {
  bucket = aws_s3_bucket.airflow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "data_lake_raw" {
  bucket = aws_s3_bucket.data_lake_raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "data_lake_processed" {
  bucket = aws_s3_bucket.data_lake_processed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "data_lake_curated" {
  bucket = aws_s3_bucket.data_lake_curated.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "airflow_logs" {
  bucket = aws_s3_bucket.airflow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}