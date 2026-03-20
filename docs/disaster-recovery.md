# Disaster Recovery

## Recovery Objectives

| Objective | Target | Basis |
|---|---|---|
| **RTO** (Recovery Time Objective) | < 15 minutes | ECS auto-replacement + RDS Multi-AZ failover |
| **RPO** (Recovery Point Objective) | < 5 minutes | RDS automated backups (continuous WAL) + S3 versioning |

These are validated quarterly through automated chaos experiments using **AWS FIS**.

---

## Backup Strategy

### RDS PostgreSQL

| Backup Type | Mechanism | Retention | RPO Coverage |
|---|---|---|---|
| Automated daily snapshots | RDS automated backups | 7 days (dev), 14 days (prod) | Point-in-time to any second |
| Transaction log streaming | Continuous WAL archival | Included in backup window | < 5 minutes data loss |
| Manual snapshots | Pre-deployment snapshot | Indefinite (manual delete) | Zero-loss rollback |
| Cross-region copy | RDS snapshot copy | 7 days in DR region | Regional disaster |

**RDS backup configuration (Terraform):**
```hcl
backup_retention_period   = 14          # days
backup_window             = "03:00-04:00" # UTC, low-traffic window
maintenance_window        = "Mon:04:00-Mon:05:00"
deletion_protection       = true        # prevents accidental delete
skip_final_snapshot       = false       # always snapshot on destroy
copy_tags_to_snapshot     = true        # ensure traceability
```

**Point-in-time restore:**
```bash
# Restore to a specific second (within backup retention window)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier ecs-enterprise-prod-rds \
  --target-db-instance-identifier ecs-enterprise-prod-rds-restored \
  --restore-time 2024-01-15T10:00:00Z \
  --db-subnet-group-name ecs-enterprise-prod-rds-subnet
```

### Terraform State

Terraform state is the "source of truth" for infrastructure. Loss = inability to manage infra via Terraform.

| Backup | Mechanism | Recovery |
|---|---|---|
| S3 versioning | Enabled on state bucket | `aws s3api get-object --version-id` |
| DynamoDB locks | Point-in-time recovery enabled | PITR restore |
| State encryption | SSE-KMS | KMS key backed up via key policy |

**State recovery:**
```bash
# List state versions
aws s3api list-object-versions \
  --bucket ecs-enterprise-platform-terraform-state \
  --prefix terraform/prod/terraform.tfstate

# Restore specific version
aws s3api get-object \
  --bucket ecs-enterprise-platform-terraform-state \
  --key terraform/prod/terraform.tfstate \
  --version-id <version-id> \
  terraform.tfstate.backup
```

### Application Container Images

ECR images are tagged with Git SHA and stored permanently (lifecycle policy keeps last 50 images).

```bash
# List available images for rollback
aws ecr describe-images \
  --repository-name ecs-enterprise-prod \
  --query 'sort_by(imageDetails, &imagePushedAt)[-10:].imageTags'
```

---

## Recovery Playbooks

### Scenario 1: ECS Service Degraded (Partial Failure)

**Symptoms**: High 5xx rate, reduced throughput, CloudWatch alarm fired.

```bash
# 1. Check service health
aws ecs describe-services \
  --cluster ecs-enterprise-prod-cluster \
  --services ecs-enterprise-prod-service \
  --query 'services[0].{desired:desiredCount,running:runningCount,deployments:deployments}'

# 2. Check stopped task reasons
aws ecs list-tasks \
  --cluster ecs-enterprise-prod-cluster \
  --desired-status STOPPED | \
  jq '.taskArns[]' | xargs -I{} \
  aws ecs describe-tasks --cluster ecs-enterprise-prod-cluster --tasks {} \
  --query 'tasks[0].{stopped:stoppedReason,container:containers[0].reason}'

# 3. Force rollback to previous task revision
aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --task-definition ecs-enterprise-prod-task:<N-1> \
  --force-new-deployment

# 4. Wait for stability
aws ecs wait services-stable \
  --cluster ecs-enterprise-prod-cluster \
  --services ecs-enterprise-prod-service
```

**Expected RTO: 2–5 minutes** (circuit breaker handles this automatically; manual intervention only needed if circuit breaker doesn't trip).

### Scenario 2: RDS Failover (Primary AZ Failure)

**Symptoms**: DB connection errors, RDS event "Multi-AZ failover initiated".

Multi-AZ RDS failover is **automatic**:
```
Primary AZ fails
  → RDS detects failure (typically within 60s)
    → Standby promoted to primary
      → DNS CNAME updated (same endpoint, new IP)
        → Application reconnects (connection pool refresh)
          → Normal operation resumes
```

**Connection pool reset** (if app holds stale connections):
```bash
# Force ECS tasks to restart (fresh connections)
aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --force-new-deployment
```

**Expected RTO: 1–2 minutes** (RDS DNS propagation + connection pool refresh).

### Scenario 3: Full Region Failure (Warm Standby)

We maintain Terraform modules parameterized for multi-region deployment.

```bash
# 1. Provision standby infrastructure in DR region
cd terraform/environments/prod
terraform apply \
  -var-file=prod.tfvars \
  -var="aws_region=us-west-2" \
  -var="vpc_cidr=10.3.0.0/16"

# 2. Restore RDS from latest cross-region snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier ecs-enterprise-dr-rds \
  --db-snapshot-identifier <latest-cross-region-snapshot> \
  --region us-west-2

# 3. Update DNS (Route53 health check weight failover)
aws route53 change-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --change-batch file://dns-failover.json

# 4. Validate
curl https://api.example.com/health
```

**Expected RTO: 10–15 minutes** (constrained by RDS restore time).

### Scenario 4: SQS DLQ Recovery (Message Replay)

When messages are in the DLQ after processing failures:

```bash
# 1. Inspect DLQ messages (without deleting)
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/<account>/ecs-enterprise-prod-dlq \
  --max-number-of-messages 10 \
  --message-attribute-names All

# 2. After root cause is fixed, replay messages
# Use the SQS DLQ redrive feature (console or CLI)
aws sqs start-message-move-task \
  --source-arn arn:aws:sqs:us-east-1:<account>:ecs-enterprise-prod-dlq \
  --destination-arn arn:aws:sqs:us-east-1:<account>:ecs-enterprise-prod-queue \
  --max-number-of-messages-per-second 10  # throttle replay

# 3. Monitor replay progress
aws sqs get-message-move-task-attributes \
  --task-handle <task-handle>
```

---

## DR Testing Schedule

| Test | Frequency | Method | Pass Criteria |
|---|---|---|---|
| ECS rollback | Monthly | GitHub Actions deploy + revert | Service stable in < 3 min |
| RDS failover simulation | Quarterly | AWS FIS `aws:rds:failover-db-cluster` | App reconnects in < 2 min |
| DLQ replay | Monthly | Inject test messages into DLQ | Messages processed correctly |
| Full region failover | Annually | Spinup DR region + DNS cut | RTO < 15 min achieved |
| Backup restore | Quarterly | RDS PITR to test instance | Data integrity verified |

**All DR tests are documented in the `docs/runbooks/` directory** with pass/fail history.

---

## Data Residency & Compliance

- Primary region: `us-east-1` (Virginia)
- DR region: `us-west-2` (Oregon) — US-only, meets data residency for most US compliance frameworks
- RDS encrypted at rest: KMS CMK per environment
- S3 state bucket: SSE-KMS, versioning enabled
- CloudTrail: All regions, immutable S3 destination
- VPC Flow Logs: 90-day retention for forensic analysis
