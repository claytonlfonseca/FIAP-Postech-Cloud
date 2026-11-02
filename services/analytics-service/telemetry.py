import os
import logging

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

log = logging.getLogger(__name__)


def init_telemetry(app):
    """Configura o OpenTelemetry (traces via OTLP/HTTP).

    O endpoint é lido de OTEL_EXPORTER_OTLP_ENDPOINT (ex: http://otel-collector:4318).
    Falhas aqui não derrubam o serviço.
    """
    try:
        resource = Resource.create(
            {"service.name": os.getenv("OTEL_SERVICE_NAME", "analytics-service")}
        )
        provider = TracerProvider(resource=resource)
        provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
        trace.set_tracer_provider(provider)

        FlaskInstrumentor().instrument_app(app)
        BotocoreInstrumentor().instrument()  # SQS e DynamoDB
        log.info("OpenTelemetry inicializado.")
    except Exception as e:
        log.error(f"Falha ao iniciar OpenTelemetry (seguindo sem tracing): {e}")
