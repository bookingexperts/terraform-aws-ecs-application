# Routing from external -> interal is managed manually on the proxies
resource "aws_route53_record" "hostname" {
  zone_id = var.route53_zones.external.zone_id
  name    = local.subdomain
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = var.load_balancers.external.dns_name
    zone_id                = var.load_balancers.external.zone_id
  }
}

resource "aws_route53_record" "wildcard" {
  zone_id = var.route53_zones.external.zone_id
  name    = "*.${local.subdomain}"
  type    = "A"

  alias {
    evaluate_target_health = true
    name                   = var.load_balancers.external.dns_name
    zone_id                = var.load_balancers.external.zone_id
  }
}

resource "aws_route53_record" "cdn" {
  for_each = toset(concat([local.cloudfront_host], local.cloudfront.aliases))
  zone_id  = var.route53_zones.external.zone_id
  name     = each.value
  type     = "A"

  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
  }
}

