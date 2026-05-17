# Product Requirements Document: ollama-observability

## 1. Product Overview
**Name:** `ollama-observability`
**Role in Ecosystem:** Instrumentation and telemetry layer.
**Goal:** Expose enterprise-grade metrics, distributed tracing, and structured logging for Ollama inference operations.

## 2. Strategic Positioning
This gem intercepts hooks from `ollama-client` (e.g., `on_response`, stream callbacks) and translates them into standard observability formats. It relies strictly on the `ollama-client` hooks and does not monkey-patch transport internals.

## 3. System Requirements & Features
### 3.1. OpenTelemetry Integration
- Generate tracing spans for all core operations: `ollama.chat`, `ollama.embed`, `ollama.pull`.
- Capture metadata in span attributes (model name, prompt tokens, completion tokens, finish reason).

### 3.2. Metrics
- Expose histograms for latency (time-to-first-token, total generation time).
- Expose counters for token usage (prompt, completion) and error rates.
- Prometheus-compatible exporter support.

### 3.3. Structured Logging
- JSON-formatted log output encapsulating request/response metadata without dumping massive PII/PHI payloads (configurable payload redaction).

## 4. Implementation Details
- **Dependencies:** `ollama-client`, `opentelemetry-sdk`, `opentelemetry-api`.
- **Instrumentation:** Implement an `Ollama::Observability::Instrumentor` that subscribes to the client's `on_response` and hook callbacks.

## 5. Non-Goals
- Do not build a standalone APM platform.
- Do not implement custom transport tracking—rely on the client's hook contracts.
