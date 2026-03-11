# Observability Strategy

## CloudWatch setup
- **CloudWatch Logs**: All services stream to `/ecs/ecs-platform-production`. Retention set to 30 days for cost-efficiency vs visibility.
- **CloudWatch Alarms**: 
  - CPU/Memory > 80% for 3 periods of 1 minute.
  - 5xx errors > 1% of total traffic.

## Prometheus & Grafana
- **Prometheus**: Run as a sidecar in ECS or a standalone service (Managed Service for Prometheus). 
- **Metric Scraping**: Use ADOT (AWS Distro for OpenTelemetry) for automatic scraping of ECS task metrics.
- **Grafana Dashboards**: Centralized view for:
  - Container health.
  - API latency (p95, p99).
  - Step Function failure rates.
