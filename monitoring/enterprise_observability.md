# Enterprise Observability Strategy

## 1. Golden Signals Monitoring (SRE focus)
- **Latency**: p99 and p95 metrics for all API Gateway endpoints.
- **Traffic**: Request count per second, split by status code.
- **Errors**: 5xx error rate alarm (threshold > 1%).
- **Saturation**: ECS CPU/Memory usage vs. Limits.

## 2. Advanced Alerting Logic
- **CloudWatch Metric Filters**: 
  - Scan application logs for `ERROR` strings and increment a custom metric.
  - Alarm if `ERROR` count > 10 in 1 minute.
- **SNS Integration**: Direct alerts to `devops-oncall` email/Slack/PagerDuty.

## 3. Distributed Tracing
- **AWS X-Ray**: Enabled on API Gateway and ECS Tasks to visualize service dependencies and identify bottlenecks.

## 4. Operational Dashboards
- **Executive Dashboard**: High-level availability and throughput.
- **Engineering Dashboard**: Latency breakdown, container restarts, and secret rotation status.
