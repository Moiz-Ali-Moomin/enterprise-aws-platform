# ADR 002: Use AWS ADOT Collector for Observability

## Status
Accepted

## Context
The application needs to export distributed traces and metrics to AWS X-Ray and CloudWatch. Standard OpenTelemetry SDKs are used in the application, but they need a collector to aggregate and export data efficiently.

## Decision
We chose the AWS Distro for OpenTelemetry (ADOT) collector, deployed as a sidecar container in the ECS task definition.

## Consequences
- **Pros**: Standard OTLP protocol used in application code, simplified export to AWS services, provides a local buffer for spans/metrics, and supports advanced processing (attributes, sampling).
- **Cons**: Additional resource overhead (~100-200MB RAM) per task.
