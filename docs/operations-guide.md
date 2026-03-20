# Operations Guide

## Operational Philosophy

This platform follows **Automated Reliability Engineering (ARE)**: manual intervention is a last resort. Every failure mode has an automated response; runbooks exist for the exceptions.

**Principles:**
1. Alerts should indicate actionable problems, not noise.
2. Every alert should have a corresponding runbook.
3. Dashboards should answer "what is wrong?" without requiring Athena queries.
4. Traces should answer "where did this request fail?" in under 2 minutes.

---

## 1. Metrics

### Infrastructure Metrics (CloudWatch)

All ECS and ALB metrics are available in CloudWatch natively. Key metrics tracked:

| Metric | Namespace | Alarm Threshold | Severity |
|---|---|---|---|
| `CPUUtilization` | `AWS/ECS` | > 80% for 5 min | P1 |
| `MemoryUtilization` | `AWS/ECS` | > 80% for 5 min | P1 |
| `RunningTaskCount` | `AWS/ECS` | < 1 for 2 min | P0 |
| `HTTPCode_Target_5XX_Count` | `AWS/ApplicationELB` | > 10/min | P1 |
| `RequestCount` | `AWS/ApplicationELB` | Anomaly detection | P2 |
| `TargetResponseTime` | `AWS/ApplicationELB` | p99 > 2s | P1 |
| `ApproximateNumberOfMessagesVisible` | `AWS/SQS` | > 1000 for 10 min | P2 |
| `NumberOfMessagesSent` to DLQ | `AWS/SQS` | > 0 | P1 |

**Latency targets:**
- `Latency (p50)`: < 50ms
- `Latency (p99)`: < 200ms
- `Availability`: 99.99% monthly

### Application Metrics (CloudWatch EMF via ADOT)

The ADOT sidecar receives OTLP metrics from the app and exports them using **Embedded Metric Format (EMF)** — structured log lines that CloudWatch automatically parses into metrics with zero additional cost.

Custom metrics include:
- `order.processing.duration` — histogram of order processing time
- `queue.messages.processed` — counter per worker task
- `db.query.duration` — database query latency percentiles

### Prometheus Integration (Optional)

The application exposes a `/metrics` endpoint (Prometheus format) via `prometheus-fastapi-instrumentator`. To scrape:

```yaml
# Prometheus scrape config (if running Prometheus/Grafana)
scrape_configs:
  - job_name: 'ecs-api-service'
    ec2_sd_configs:  # or use ECS service discovery
      - region: us-east-1
        filters:
          - name: tag:Environment
            values: [prod]
```

---

## 2. Logs

### Log Architecture

```
Application Container
  → stdout/stderr (JSON structured)
    → awslogs driver
      → CloudWatch Log Group: /ecs/{project}-{env}
        Stream prefix: app
        Retention: 30 days
        Encryption: KMS (per-log-group key)

ADOT Sidecar
  → stdout/stderr
    → awslogs driver
      → CloudWatch Log Group: /ecs/{project}-{env}
        Stream prefix: adot

VPC Flow Logs
  → CloudWatch Log Group: /aws/vpc-flow-log/{project}-{env}
    Retention: 90 days
    Encryption: KMS
```

### Structured Log Format

All application logs are emitted as JSON:

```json
{
  "timestamp": "2024-01-15T10:23:45.123Z",
  "level": "INFO",
  "logger": "api.orders",
  "message": "Order processed successfully",
  "trace_id": "1-65a4f3b2-abc123def456789012345678",
  "span_id": "abc1234567890123",
  "service": "ecs-enterprise-prod",
  "environment": "prod",
  "order_id": "ord-789",
  "duration_ms": 145
}
```

**Key fields:**
- `trace_id`: AWS X-Ray format (`1-{timestamp-hex}-{random-hex}`). Links log entries to distributed traces.
- `span_id`: The specific span within the trace. Identifies which exact operation generated this log.
- `service`: Service name (matches `OTEL_SERVICE_NAME`). Used for cross-service correlation.

### Querying Logs

**CloudWatch Insights queries:**

```sql
-- Find all errors for a specific trace
fields @timestamp, level, message, trace_id, span_id
| filter trace_id = "1-65a4f3b2-abc123def456789012345678"
| sort @timestamp asc

-- Error rate by hour
stats count() as errors by bin(1h)
| filter level = "ERROR"

-- Slow requests (p99 latency)
stats percentile(duration_ms, 99) as p99 by bin(5m)
| filter ispresent(duration_ms)

-- DLQ message failures
fields @timestamp, message, order_id, error
| filter @log like /worker/
| filter level = "ERROR"
| sort @timestamp desc
| limit 50
```

---

## 3. Distributed Tracing

### Trace Architecture (OpenTelemetry + ADOT + X-Ray)

```
HTTP Request arrives at ALB
  → ALB generates/propagates X-Amzn-Trace-Id header
    → FastAPI app (instrumented with opentelemetry-sdk)
      → Auto-instrumentation creates root span
        → Business logic spans created:
            span: "process_order"
              span: "db.query" (SQLAlchemy auto-instrumented)
              span: "sqs.publish" (boto3 auto-instrumented)
        → OTLP exporter sends spans to ADOT sidecar (localhost:4317)
          → ADOT collector exports to AWS X-Ray
            → X-Ray assembles trace segments into Service Map
```

### How trace_id and span_id Enable Debugging

**`trace_id`** is the global correlation ID for one end-to-end request:
- Same `trace_id` appears in: application logs, ADOT metrics, X-Ray traces, SQS message attributes, worker logs.
- Allows you to reconstruct the full lifecycle of a single user request across all services.

**`span_id`** identifies one unit of work within a trace:
- Each function call, DB query, or external API call gets its own span.
- Parent-child relationships form the trace tree.
- When a span fails, its `span_id` + error details pinpoint the exact failure.

### End-to-End Debugging Workflow

**Scenario**: User reports "my order isn't showing up" at 14:23 UTC.

```
Step 1 — Find the trace
  X-Ray Service Map → filter by 14:20–14:25 UTC → filter by 5xx or "order not found"
  → Copy trace_id: "1-65a4f3b2-abc123def456789012345678"

Step 2 — Inspect the trace
  X-Ray → Traces → paste trace_id
  → See full call graph: ALB → API → DB query (failed, 512ms, timeout)
  → Span details: DB query timeout at 14:23:47 UTC, span_id: "abc123"

Step 3 — Correlate with logs
  CloudWatch Insights:
    filter trace_id = "1-65a4f3b2-abc123def456789012345678"
  → Find: DB connection pool exhausted, 4 prior retries, final timeout

Step 4 — Check worker (if async)
  SQS DLQ — message attributes contain trace_id
  → Worker log group filtered by same trace_id
  → Find worker failed 3 times with same DB error

Step 5 — Root cause
  CloudWatch Metrics → RDS FreeableMemory → dropped to 50MB at 14:22 UTC
  → RDS was under memory pressure → query queue backed up → timeouts
```

**Total investigation time < 5 minutes** with correlated trace_id across all systems.

### ADOT Configuration

ADOT is configured via SSM Parameter Store (`/{project}/{env}/adot-config`):

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317   # Application sends traces here
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch/traces:
    timeout: 1s
    send_batch_size: 50          # Group spans for efficiency
  batch/metrics:
    timeout: 60s

exporters:
  awsxray: {}                    # Traces → X-Ray
  awsemf:
    log_group_name: '/aws/ecs/metrics'
    log_stream_name: 'otel-metrics'   # Metrics → CloudWatch EMF

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch/traces]
      exporters: [awsxray]
    metrics:
      receivers: [otlp]
      processors: [batch/metrics]
      exporters: [awsemf]
```

---

## 4. Alerting & Escalation

### Alert Routing

```
CloudWatch Alarm → SNS Topic → {
  Email:        devops-oncall@company.com
  PagerDuty:    PagerDuty SNS integration (P0/P1 only)
  Slack:        AWS Chatbot → #alerts-prod channel
}
```

### Severity Levels

| Severity | Response Time | Examples | Auto-Remediation |
|---|---|---|---|
| **P0** | < 5 min | Running tasks < 1, total outage | ECS circuit breaker rolls back |
| **P1** | < 15 min | CPU > 80%, 5xx rate spike, DLQ messages | Auto-scaling triggers |
| **P2** | < 1 hour | High latency, anomalous request rate | — |
| **P3** | Next business day | Non-critical, capacity planning | — |

---

## 5. Scaling Procedures

### ECS Auto-Scaling (Automatic)

Target tracking policies manage ECS task count automatically:
- **Scale-out triggers**: CPU > 70% OR Memory > 80% sustained for 60s.
- **Scale-in**: Waits 300s to prevent thrashing.
- **Min/Max**: 2–10 tasks (configurable per environment).

### Queue-Based Worker Scaling

Workers scale on SQS `ApproximateNumberOfMessagesVisible`:
```bash
# Manual check: current queue depths
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=ecs-enterprise-prod-queue \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Average
```

### Manual Scale Override

```bash
# Force ECS service to N tasks immediately
aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --desired-count 5
```

---

## 6. Maintenance Protocols

### Routine

| Task | Frequency | Automation |
|---|---|---|
| Secret rotation | Every 30 days | Lambda + Secrets Manager rotation |
| Log archival | Continuous | S3 lifecycle: Glacier after 90 days |
| ECR lifecycle | Weekly | ECR lifecycle policy (keep last 5 tagged) |
| Dependency updates | Weekly | Dependabot PRs |
| Trivy DB update | Each CI run | GitHub Actions cache with daily invalidation |

### Deployment Procedure

Standard deployments are fully automated via GitHub Actions. For emergency manual deployments:

```bash
# 1. Build and push image
docker build -t $ECR_REPO:hotfix-$(date +%s) ./services/api-service
docker push $ECR_REPO:hotfix-$(date +%s)

# 2. Register new task definition
aws ecs register-task-definition --cli-input-json file://task-def.json

# 3. Deploy with stability wait
aws ecs update-service \
  --cluster ecs-enterprise-prod-cluster \
  --service ecs-enterprise-prod-service \
  --task-definition ecs-enterprise-prod-task:<new-revision>
aws ecs wait services-stable \
  --cluster ecs-enterprise-prod-cluster \
  --services ecs-enterprise-prod-service
```

---

## 7. Troubleshooting Reference

| Symptom | First Check | Command |
|---|---|---|
| ECS deployment stuck | Circuit breaker events | `aws ecs describe-services --services <name>` |
| High 5xx rate | ALB access logs + X-Ray errors | CloudWatch Insights: `filter @message like /ERROR/` |
| Task failing to start | ECS stopped task reason | `aws ecs describe-tasks --tasks <task-arn>` |
| Image pull failure | ECR auth + VPC endpoint | Check ECS execution role ECR permissions |
| DLQ messages accumulating | Worker logs + trace | Filter logs by `trace_id` from DLQ message attribute |
| Memory pressure | RDS metrics | CloudWatch → RDS → FreeableMemory |
| NAT timeout (residual) | Egress security group | Verify security group allows HTTPS to VPC CIDR |
