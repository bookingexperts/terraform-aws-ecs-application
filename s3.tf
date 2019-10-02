locals {
  s3_defaults = {
    bucket_name = local.name
    allow_uploads = false
    auto_expire_paths = []
  }
  s3 = merge(local.s3_defaults, var.s3)
}

resource "aws_s3_bucket" "media" {
  bucket        = local.s3.bucket_name
  acl           = "private"
  force_destroy = true

  policy = <<EOF
{
    "Version": "2008-10-17",
    "Id": "PolicyForCloudFrontPrivateContent",
    "Statement": [
        {
            "Sid": "1",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${aws_cloudfront_origin_access_identity.default.iam_arn}"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${local.s3.bucket_name}/*"
        }
    ]
}
EOF

  dynamic "cors_rule" {
    for_each = local.s3.allow_uploads ? [true] : []
    content {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "GET", "HEAD"]
      allowed_origins = ["https://${local.hostname}"]
      expose_headers  = ["ETag"]
    }
  }

  dynamic "lifecycle_rule" {
    for_each = compact(local.s3.auto_expire_paths)
    content {
      prefix = replace(lifecycle_rule.value, "/^//", "")
      enabled = true
      abort_incomplete_multipart_upload_days = 1
      expiration {
        days = 1
      }
    }
  }

  tags = {
    workload-type = var.workload_type
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = false
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
