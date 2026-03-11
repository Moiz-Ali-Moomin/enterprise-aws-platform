output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.main.domain_name
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}
