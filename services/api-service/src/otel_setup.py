"""
OpenTelemetry Setup for AWS ADOT Collector

Configures distributed tracing and metrics export via OTLP
to the ADOT sidecar container running on localhost.
"""

import os

from opentelemetry import trace, metrics
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter


def setup_telemetry() -> None:
    """Initialize OpenTelemetry tracing and metrics providers."""
    service_name = os.getenv("OTEL_SERVICE_NAME", "api-service")
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
    environment = os.getenv("ENVIRONMENT", "production")

    resource = Resource(attributes={
        SERVICE_NAME: service_name,
        "deployment.environment": environment,
    })

    # Tracing
    tracer_provider = TracerProvider(resource=resource)
    span_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))
    trace.set_tracer_provider(tracer_provider)

    # Metrics
    metric_exporter = OTLPMetricExporter(
        endpoint=otlp_endpoint.replace("4317", "4318") + "/v1/metrics"
    )
    metric_reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=60000)
    meter_provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
    metrics.set_meter_provider(meter_provider)


def instrument_app(app) -> None:
    """Instrument a FastAPI application with OpenTelemetry."""
    FastAPIInstrumentor.instrument_app(app)
