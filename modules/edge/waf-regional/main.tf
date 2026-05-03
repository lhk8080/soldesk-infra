resource "aws_wafv2_web_acl" "main" {
  name        = "ticketing-waf-regional"
  scope       = "REGIONAL"
  description = "Web ACL for ops IngressGroup ALB"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "TicketingWAFRegional"
    sampled_requests_enabled   = true
  }

  tags = { Name = "ticketing-waf-regional", Environment = var.env }
}
