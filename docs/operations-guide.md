# Operations Guide

## Operational Philosophy
We practice **Automated Reliability Engineering (ARE)**. Manual intervention should be a last resort.

## 1. Monitoring & Alerting
Metrics are routed to CloudWatch and Grafana.
- **P0 Alerts**: Trigger remediation controllers.
- **P1 Alerts**: Notify devops-oncall via SNS.

### Critical Metrics
- `Latency (p99)`: Target < 200ms
- `Availability`: Target 99.99%
- `Error Budget`: Block deploy if < 1h remaining per month.

## 2. Scaling Procedures
ECS services use **Target Tracking Scaling**.
- **Scale Up**: Triggered at 70% CPU/Memory.
- **Scale Down**: Triggered at 30% utilization.

## 3. Maintenance Protocols
### Routine Tasks
- **Secret Rotation**: Automated by Lambda every 30 days.
- **Log Archival**: S3 lifecycle policies move logs to Glacier after 90 days.

### Manual Maintenance
Use Ansible playbooks for bulk operations:
```bash
ansible-playbook ansible/ops_maintenance.yml -i inventory.aws_ec2.yml
```

## 4. Troubleshooting
1. **ECS Deployment Failure**: Check `Deployment Circuit Breaker` events in the ECS console.
2. **Network Timeout**: Verify VPC Lattice AuthZ policies and Security Group rules.
3. **WAF Block**: Inspect CloudFront logs for "Blocked" status codes.
