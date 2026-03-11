# Incident Response Runbook (Enterprise Platform)

## 1. High-Severity Incidents (P0/P1)

### A. Total Site Outage (CloudFront/APIG)
- **Detection**: CloudWatch Alarm `TotalAvailabilityMetric < 99.9%`.
- **Immediate Action**: 
  - Check CloudFront logs for WAF 403 blocks (possible DDoS).
  - Verify API Gateway service limits.
  - Scale up ECS cluster replicas if latency is spiking.
- **Rollback Tool**: `scripts/ops_tool.py get-logs --log-group /ecs/api-service` to identify breaking changes.

### B. Security Breach (Data Exfiltration)
- **Detection**: GuardDuty finding "Exfiltration:S3/AnomalousBehavior".
- **Immediate Action**: 
  - Revoke affected IAM role sessions.
  - Rotate Secret Keys immediately via Secrets Manager Console or `scripts/secret_rotator.py`.
  - Isolate affected VPC resources via Security Group lock-down (0.0.0.0/0 -> Deny).

## 2. Low-Severity Incidents (P2/P3)

### A. Slow Performance / High p99 Latency
- **Detection**: Grafana Latency Dashboard (p99 > 500ms).
- **Immediate Action**:
  - Analyze X-Ray traces to find the slow component (SFN vs. ECS).
  - Check RDS CPU utilization; scale instance size via Terraform if necessary.

## 3. Post-Incident Process
1.  **Freeze CI/CD**: Disable GitHub Actions pipelines.
2.  **Conduct Root Cause Analysis (RCA)**.
3.  **Update IaC**: Implement preventative Terraform rules (e.g., tighter WAF limits).
