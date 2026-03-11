# ⚠️ Experimental Modules

> **WARNING**: The modules in this directory are **experimental** and are **NOT** referenced by any environment configuration (dev, staging, or prod).

These modules are exploratory implementations for future features. They have **NOT** been tested or validated for production use.

## Modules

| Module | Purpose | Status |
|--------|---------|--------|
| `apigateway/` | API Gateway integration | Experimental |
| `app_mesh/` | AWS App Mesh service mesh | Experimental |
| `cloudfront_waf/` | CloudFront + WAF distribution | Experimental |
| `lambda/` | Lambda function integration | Experimental |
| `sqs/` | SQS queue management | Experimental |
| `step_functions/` | Step Functions workflows | Experimental |
| `vpc_lattice/` | VPC Lattice service networking | Experimental |

## Usage

Do **NOT** reference these modules from environment configurations unless they have been:

1. Fully reviewed and tested
2. Security-audited
3. Promoted to `terraform/modules/` (the production module directory)
