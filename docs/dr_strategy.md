# Disaster Recovery & Global Resilience Strategy

## 1. Objectives (RTO/RPO)

- **Recovery Time Objective (RTO)**: < 15 minutes. The time taken to switch traffic to the secondary region.
- **Recovery Point Objective (RPO)**: < 5 minutes. The maximum amount of data loss acceptable (governed by cross-region replication latency).

## 2. Multi-Region Architecture: "Pilot Light" to "Warm Standby"

- **Primary Region**: `us-east-1` (Virginia). All active traffic.
- **Secondary Region**: `us-west-2` (Oregon). Infrastructure pre-provisioned.
- **Data Replication**:
  - **S3 State**: Cross-Region Replication (CRR) enabled.
  - **DynamoDB**: Global Tables (Active-Active replication).
  - **RDS (Optional)**: Cross-region Read Replicas.

## 3. Failover Mechanism

- **Route53 Global Health Checks**: Monitor the `us-east-1` Application Load Balancer.
- **DNS Switch**: Automatic DNS failover via Route53 Failover Routing Policy.
- **Edge Layer**: CloudFront remains global, but shifts origin to the secondary ALB if the primary health check fails.

## 4. Execution Plan (Chaos testing)

- **Regional Outage Simulation**: Manually failing the primary ALB health check via FIS to verify automated traffic shift.
- **RPO Verification**: Measuring the delta between S3 object creation in East vs West.
