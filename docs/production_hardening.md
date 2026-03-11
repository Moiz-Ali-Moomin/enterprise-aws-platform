# Production Security & Hardening Guide

## 1. SOC2 Security Model

The platform aligns with SOC2 trust principles (Security, Availability, Confidentiality):

*   **Access Control**: Least-privilege IAM roles for every service. No IAM users; all access via SSO/Roles.
*   **Encryption**: 
    - At-Rest: All EBS, RDS, and S3 buckets encrypted with KMS.
    - In-Transit: SSL/TLS termination at CloudFront/API Gateway.
*   **Auditability**: CloudTrail enabled for all account activity. VPC Flow Logs for network auditing.
*   **Infrastructure as Code**: No manual changes permitted. All changes via GitHub Actions.

## 2. Failure Scenarios & Recovery (DR/HA)

| Scenario | Impact | Mitigation / Recovery |
| :--- | :--- | :--- |
| **AZ Outage** | Partial Capacity Loss | Auto-scaling groups in other AZs compensate; ALB health checks reroute traffic. |
| **Database Failure** | Service Downtime | Multi-AZ RDS failover (automatic within 60-120 seconds). |
| **Deployment Bug** | High Error Rate | GitHub Actions rollback; Route 53 or CloudFront weighted routing for Canary/Blue-Green. |
| **Regional Outage** | Total Downtime | Multi-region Terraform manifests ready for rapid restoration (Pilot Light model). |

## 3. Production Hardening Checklist

1.  **WAF Hardening**: Enable rate limiting (e.g., 2000 requests per IP per 5 min) and block known malicious IPs.
2.  **Shield Standard**: Enabled by default; consider Shield Advanced for higher SLA and DDoS response team access.
3.  **Security Hub**: Enable at the account level to aggregate findings from GuardDuty, Inspector, and Config.
4.  **Secrets Rotation**: Enable automatic rotation for RDS/API keys in Secrets Manager using Lambda.
5.  **Drift Detection**: Run `terraform plan` on a schedule to detect and remediate manual infra changes.

## 4. Operational Runbook (Incident Handling)

*   **Step 1: Triage**: Detect via CloudWatch Alarm -> Notify via PagerDuty.
*   **Step 2: Isolation**: Block offending IPs via WAF or scale up ECS cluster.
*   **Step 3: Investigation**: Use `ops_tool.py get-logs` and CloudWatch Insights.
*   **Step 4: Resolution**: Apply hotfix via CI/CD or trigger `ops_maintenance.yml` for manual intervention.
*   **Step 5: Post-Mortem**: Document root cause and implement preventative Terraform/IAM measures.
