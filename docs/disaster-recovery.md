# Disaster Recovery & Regional Failover

## Disaster Recovery Objectives
- **RTO (Recovery Time Objective)**: 15 minutes.
- **RPO (Recovery Point Objective)**: 5 minutes.

## Strategy: Warm Standby (Multi-Region)
We maintain a primary region (`us-east-1`) and a pre-provisioned secondary region (`us-west-2`).

### 1. Data Replication
- **DynamoDB**: Global Tables ensure active-active replication.
- **S3**: Cross-Region Replication (CRR) for state and mission-critical buckets.
- **Secrets**: Replicated to the secondary region via Secrets Manager native replication.

### 2. Automatic Failover
Route53 health checks monitor the Primary ALB.
1. If health check fails for 3 consecutive intervals (90s).
2. Global Accelerator shifts a % of traffic to the Secondary Regional Endpoint.
3. Once the Secondary passes health checks, 100% of traffic is routed to West.

### 3. Manual failover (Break Glass)
In case of complex failures, use the `scripts/ops_tool.py` to trigger a manual shift:
```bash
python scripts/ops_tool.py failover --target us-west-2
```

## DR Testing Schedule
Chaos experiments are run monthly using **AWS FIS** to simulate regional isolation and verify failover logic.
