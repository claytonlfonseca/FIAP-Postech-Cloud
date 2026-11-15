package main

import (
	"context"
	"errors"
	"os"

	"github.com/go-redis/redis/v8"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

func initTracer(c context.Context) (func(context.Context) error, error) {
	exporter, err := otlptracehttp.New(c)
	if err != nil {
		return nil, err
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = "evaluation-service"
	}

	res, err := resource.New(c,
		resource.WithFromEnv(),
		resource.WithAttributes(semconv.ServiceName(serviceName)),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, propagation.Baggage{},
	))

	return tp.Shutdown, nil
}

// redisTracingHook cria spans OpenTelemetry para comandos e pipelines do go-redis.
type redisTracingHook struct{}

func (h redisTracingHook) BeforeProcess(c context.Context, cmd redis.Cmder) (context.Context, error) {
	c, _ = otel.Tracer("evaluation-service/redis").Start(
		c,
		"redis "+cmd.Name(),
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			semconv.DBSystemRedis,
			attribute.String("db.operation", cmd.Name()),
			attribute.String("peer.service", "redis"),
		),
	)
	return c, nil
}

func (h redisTracingHook) AfterProcess(c context.Context, cmd redis.Cmder) error {
	span := trace.SpanFromContext(c)
	err := cmd.Err()
	if err != nil && !errors.Is(err, redis.Nil) {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
	} else if cmd.Name() == "get" {
		span.SetAttributes(attribute.Bool("cache.hit", err == nil))
	}
	span.End()
	return nil
}

func (h redisTracingHook) BeforeProcessPipeline(c context.Context, cmds []redis.Cmder) (context.Context, error) {
	c, _ = otel.Tracer("evaluation-service/redis").Start(
		c,
		"redis pipeline",
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			semconv.DBSystemRedis,
			attribute.Int("db.redis.pipeline_length", len(cmds)),
			attribute.String("peer.service", "redis"),
		),
	)
	return c, nil
}

func (h redisTracingHook) AfterProcessPipeline(c context.Context, cmds []redis.Cmder) error {
	span := trace.SpanFromContext(c)
	for _, cmd := range cmds {
		if err := cmd.Err(); err != nil && !errors.Is(err, redis.Nil) {
			span.RecordError(err)
			span.SetStatus(codes.Error, err.Error())
			break
		}
	}
	span.End()
	return nil
}
