# Advanced Patterns Module Collection

This directory contains **production-grade advanced AWS pattern implementations** that demonstrate architectural depth beyond the core platform.

These modules are designed to:

- Showcase real-world AWS infrastructure patterns encountered at scale
- Serve as reference implementations for platform engineers
- Demonstrate trade-off thinking: each module has a README explaining why you would and would not use it

## Modules

| Module | Pattern | When to Use |
|---|---|---|
| [`apigateway/`](apigateway/) | API Gateway v2 (HTTP) + Lambda integration | Public-facing APIs requiring per-route auth, rate limiting, or usage plans |
| [`app_mesh/`](app_mesh/) | AWS App Mesh service mesh | Multi-service ECS environments needing mTLS, circuit breaking at the network layer, and observability without code changes |
| [`cloudfront_waf/`](cloudfront_waf/) | CloudFront CDN + WAF v2 | Global content delivery, DDoS protection, OWASP rules in front of ALB |
| [`lambda/`](lambda/) | Lambda function with VPC + IAM | Event-driven compute for async tasks, cron jobs, or lightweight API backends |
| [`sqs/`](sqs/) | SQS queue + DLQ + CloudWatch alarms | Decoupling services with guaranteed delivery; see main platform's `modules/sqs` for the core version |
| [`step_functions/`](step_functions/) | Step Functions workflow | Long-running, multi-step business workflows with retry logic and state tracking |
| [`vpc_lattice/`](vpc_lattice/) | VPC Lattice service networking | Cross-account, cross-VPC service-to-service communication with native IAM auth (zero-trust without a service mesh) |

## Design Philosophy

Each module demonstrates the **staff-level engineering discipline** of:

1. **Knowing when NOT to use a pattern**: every module documents its anti-use-cases.
2. **Understanding cost implications**: advanced patterns often introduce operational complexity and cost; these are called out explicitly.
3. **Security by default**: all modules use least-privilege IAM, private networking, and encryption at rest.

## Usage

These are **reference modules** that can be instantiated from any environment:

```hcl
# Example: Add CloudFront + WAF in front of your ALB
module "cloudfront_waf" {
  source = "../../modules/advanced-patterns/cloudfront_waf"

  project_name = var.project_name
  environment  = var.environment
  alb_dns_name = module.loadbalancer.alb_dns_name
  alb_arn      = module.loadbalancer.alb_arn
  waf_acl_arn  = var.waf_acl_arn
}
```

## Relationship to Core Platform

The core platform (`modules/vpc`, `modules/ecs`, `modules/loadbalancer`, etc.) handles the baseline required by all environments.

Advanced patterns are **additive** — they layer on top without modifying the core.

## Interview Talking Points

When discussing these patterns in a technical interview:

- **App Mesh vs VPC Lattice**: App Mesh requires Envoy sidecar injection (complexity); VPC Lattice is managed by AWS and integrates natively with IAM (simpler, newer).
- **Step Functions vs SQS**: Step Functions for workflows with branching, error handling, and state tracking; SQS for simple fan-out or first-in-first-out queuing.
- **CloudFront vs ALB WAF**: CloudFront WAF runs at edge (before traffic hits your VPC); ALB WAF runs within your account. CloudFront is better for DDoS; ALB WAF has lower latency for regional traffic.
