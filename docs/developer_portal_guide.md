# Internal Developer Portal: Service Onboarding Guide

Welcome to the Elite SaaS Platform. This guide ensures your service meets our hyperscale standards from Day 1.

## 1. Quick Start: Vending a New Service
Use our **Service Blueprint** to provision your infrastructure in minutes.

```hcl
module "my_service" {
  source = "git::https://github.com/org/platform-blueprints.git//microservice?ref=v2.1"
  
  service_name = "catalog-api"
  owner        = "team-alpha"
  cost_center  = "alpha-101"
}
```

## 2. Elite Standards Checklist
- **Zero Trust**: All internal calls must use IAM signatures (VPC Lattice).
- **Hardened**: Containers run with Read-Only root filesystems.
- **Observable**: OpenTelemetry instrumentation is mandatory (included in Blueprint).
- **Resilient**: SQS buffering is required for all state-changing operations.

## 3. Deployment Safety boundaries
- **Policy Checks**: Your PR will be blocked if it violates Checkov/Terraform policies.
- **Canary Gates**: 10% traffic for 10 mins is the default rollout pattern.
- **Error Budgets**: Continuous deployment is disabled if your 30-day error budget is depleted.

## 4. Operational Self-Healing
If our CloudWatch Alarms detect a "Flapping Service", our **Remediation Controllers** will automatically scale up your tasks or rollback the last deployment.
