locals {
  cloudfront_defaults = {
    fallback_host =  null
    private_media_paths = []
    public_media_paths  = []
    aliases             = []
  }
  cloudfront = merge(local.cloudfront_defaults, var.cloudfront)
  cloudfront_host = regex("^(.+?)[.]?$", "cdn.${local.subdomain}.${var.route53_zones.external.name}")[0]
}

resource "aws_acm_certificate" "cdn" {
  provider          = "aws.cdn"
  domain_name       = local.cdn_host
  subject_alternative_names = local.cloudfront.aliases
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cdn-validation" {
  count = length(local.cloudfront.aliases) + 1

  name    = aws_acm_certificate.cdn.domain_validation_options[count.index].resource_record_name
  type    = aws_acm_certificate.cdn.domain_validation_options[count.index].resource_record_type
  records = [aws_acm_certificate.cdn.domain_validation_options[count.index].resource_record_value]
  zone_id = var.route53_zones.external.zone_id
  ttl     = 60


  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_acm_certificate_validation" "cdn" {
  provider                = "aws.cdn"
  certificate_arn         = aws_acm_certificate.cdn.arn
  validation_record_fqdns = aws_route53_record.cdn-validation.*.fqdn
}

resource "aws_cloudfront_origin_access_identity" "default" {
  provider = "aws.cdn"
  comment  = "access-identity-${local.name}.s3.amazonaws.com"
}

resource "aws_cloudfront_distribution" "cdn" {
  provider            = "aws.cdn"
  wait_for_deployment = false
  depends_on          = [aws_acm_certificate_validation.cdn, aws_acm_certificate.cdn]

  tags = {
    workload-type = var.workload_type
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Managed by Terraform"
  aliases         = concat([local.cdn_host], local.cloudfront.aliases)

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cdn.arn
    minimum_protocol_version = "TLSv1.2_2018"
    ssl_support_method       = "sni-only"
  }

  origin {
    domain_name = local.hostname
    origin_id   = "app"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_protocol_policy = "https-only"
    }
  }

  dynamic "origin" {
    for_each = compact([local.cloudfront.fallback_host])
    iterator = host

    content {
      domain_name = host.value
      origin_id   = "media-fallback"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_ssl_protocols   = ["TLSv1.2"]
        origin_protocol_policy = "https-only"
      }
    }
  }

  origin {
    domain_name = aws_s3_bucket.media.bucket_domain_name
    origin_id   = "media"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path
    }
  }

  dynamic "origin_group" {
    for_each = compact([local.cloudfront.fallback_host])

    content {
      origin_id = "media-with-fallback"

      failover_criteria {
        status_codes = [403, 404]
      }

      member {
        origin_id = "media"
      }

      member {
        origin_id = "media-fallback"
      }
    }
  }

  # Private media
  dynamic "ordered_cache_behavior" {
    for_each = local.cloudfront.private_media_paths
    iterator = path

    content {
      path_pattern           = path.value
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "media"
      compress               = true
      viewer_protocol_policy = "redirect-to-https"
      trusted_signers        = ["self"]

      forwarded_values {
        query_string = false

        cookies {
          forward = "none"
        }
      }
    }
  }

  # Public media
  dynamic "ordered_cache_behavior" {
    for_each = local.cloudfront.public_media_paths
    iterator = path

    content {
      path_pattern           = path.value
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = local.cloudfront.fallback_host == null ? "media" : "media-with-fallback"
      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      forwarded_values {
        query_string = false

        cookies {
          forward = "none"
        }
      }
    }
  }

  # Cache assets
  dynamic "ordered_cache_behavior" {
    for_each = ["/assets/*", "/packs/*"]
    iterator = path

    content {
      path_pattern           = path.value
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "app"
      compress               = true
      viewer_protocol_policy = "redirect-to-https"

      forwarded_values {
        query_string = false

        cookies {
          forward = "none"
        }
      }
    }
  }

  # Default to private
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "media"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
    trusted_signers        = ["self"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  custom_error_response {
    error_code            = "404"
    error_caching_min_ttl = 1
  }

  custom_error_response {
    error_code            = "502"
    error_caching_min_ttl = 1
  }

  custom_error_response {
    error_code            = "503"
    error_caching_min_ttl = 1
  }

  custom_error_response {
    error_code            = "504"
    error_caching_min_ttl = 1
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
