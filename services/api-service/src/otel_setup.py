"""
OpenTelemetry Setup for AWS ADOT Collector

Configures distributed tracing and metrics export via OTLP
to the ADOT sidecar container running on localhost.
"""

import os
from urllib.parse import urlparse, urlunparse

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def _metrics_endpoint(otlp_endpoint: str) -> str:
    """
    Derive the HTTP metrics endpoint from the gRPC traces endpoint.
    Replaces port 4317 (gRPC) with 4318 (HTTP) using proper URL parsing —
    not fragile string replacement.
    """
    parsed = urlparse(otlp_endpoint)
    # Switch to http scheme if needed (metrics exporter uses HTTP/protobuf)
    scheme = "http" if parsed.scheme in ("grpc", "http") else parsed.scheme
    port = 4318 if parsed.port == 4317 else (parsed.port or 4318)
    netloc = f"{parsed.hostname}:{port}"
    return urlunparse((scheme, netloc, "/v1/metrics", "", "", ""))


def setup_telemetry() -> None:
    """Initialize OpenTelemetry tracing and metrics providers."""
    service_name = os.getenv("OTEL_SERVICE_NAME", "api-service")
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
    environment = os.getenv("ENVIRONMENT", "production")

    resource = Resource(attributes={
        SERVICE_NAME: service_name,
        "deployment.environment": environment,
    })

    # Tracing — gRPC export to ADOT sidecar
    tracer_provider = TracerProvider(resource=resource)
    span_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))
    trace.set_tracer_provider(tracer_provider)

    # Metrics — HTTP/protobuf export to ADOT sidecar
    metric_exporter = OTLPMetricExporter(endpoint=_metrics_endpoint(otlp_endpoint))
    metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=60_000)
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)


def instrument_app(app) -> None:
    """Instrument a FastAPI application with OpenTelemetry."""
    FastAPIInstrumentor.instrument_app(app)
