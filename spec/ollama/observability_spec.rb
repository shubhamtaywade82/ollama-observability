# frozen_string_literal: true

require "stringio"
require "json"

RSpec.describe Ollama::Observability do
  it "has a version number" do
    expect(Ollama::Observability::VERSION).not_to be nil
  end

  describe Ollama::Observability::Instrumentor do
    let(:log_io) { StringIO.new }
    let(:instrumentor) { described_class.new(logger: Logger.new(log_io)) }
    let(:client) { Ollama::Client.new }

    it "instruments client on_response hook" do
      instrumented = instrumentor.instrument(client)
      expect(instrumented).to eq(client)

      cfg = client.instance_variable_get(:@config)
      expect(cfg.on_response).to respond_to(:call)
      expect {
        cfg.on_response.call(
          { "model" => "llama3", "prompt_eval_count" => 10, "eval_count" => 20 },
          { endpoint: "/api/chat", model: "llama3" }
        )
      }.not_to raise_error
    end

    it "traces a block with OpenTelemetry" do
      expect {
        instrumentor.trace("ollama.test") do |span|
          expect(span).not_to be_nil
        end
      }.not_to raise_error
    end

    it "instruments streaming hooks" do
      hooks = instrumentor.instrument_hooks({ on_token: ->(_t, _l = nil) {} })
      expect(hooks[:on_token]).to respond_to(:call)
      expect { hooks[:on_token].call("token", nil) }.not_to raise_error
    end

    it "redacts response payload by default" do
      instrumentor.instrument(client)
      cfg = client.instance_variable_get(:@config)
      cfg.on_response.call(
        { "model" => "llama3", "response" => "SECRET CONTENT", "prompt_eval_count" => 1, "eval_count" => 1 },
        { endpoint: "/api/generate", model: "llama3" }
      )
      expect(log_io.string).not_to include("SECRET CONTENT")
    end

    it "includes payload when redact_payloads: false" do
      ins = described_class.new(logger: Logger.new(log_io), redact_payloads: false)
      ins.instrument(client)
      cfg = client.instance_variable_get(:@config)
      cfg.on_response.call(
        { "model" => "llama3", "response" => "VISIBLE", "prompt_eval_count" => 1, "eval_count" => 1 },
        { endpoint: "/api/generate", model: "llama3" }
      )
      expect(log_io.string).to include("VISIBLE")
    end

    it "emits structured JSON log lines" do
      instrumentor.instrument(client)
      cfg = client.instance_variable_get(:@config)
      cfg.on_response.call(
        { "model" => "llama3", "prompt_eval_count" => 5, "eval_count" => 7, "total_duration" => 1_000_000 },
        { endpoint: "/api/chat", model: "llama3" }
      )
      line = log_io.string.lines.last
      payload = JSON.parse(line.split(/INFO -- :\s/).last)
      expect(payload["event"]).to eq("ollama.inference")
      expect(payload["model"]).to eq("llama3")
      expect(payload["metrics"]["prompt_tokens"]).to eq(5)
    end
  end

  describe Ollama::Observability::Prometheus do
    let(:exporter) { described_class.new }

    it "renders counters in prometheus text exposition format" do
      exporter.add_counter("ollama_tokens_total", 42, labels: { model: "llama3", kind: "prompt" })
      out = exporter.render
      expect(out).to include("# TYPE ollama_tokens_total counter")
      expect(out).to include(%(ollama_tokens_total{kind="prompt",model="llama3"} 42))
    end

    it "renders histograms with bucket samples" do
      exporter.observe_histogram("ollama_latency_ms", 120.0, labels: { model: "llama3" })
      exporter.observe_histogram("ollama_latency_ms", 800.0, labels: { model: "llama3" })
      out = exporter.render
      expect(out).to include("# TYPE ollama_latency_ms histogram")
      expect(out).to include("ollama_latency_ms_count")
      expect(out).to include("ollama_latency_ms_sum")
      expect(out).to include("ollama_latency_ms_bucket")
    end

    it "accumulates counter increments under same labels" do
      exporter.add_counter("c", 1, labels: { a: "x" })
      exporter.add_counter("c", 2, labels: { a: "x" })
      expect(exporter.render).to include(%(c{a="x"} 3))
    end
  end

  describe Ollama::Observability::LogRedactor do
    it "redacts known message content fields" do
      payload = { "messages" => [{ "role" => "user", "content" => "secret" }], "response" => "out" }
      out = described_class.call(payload)
      expect(out["messages"].first["content"]).to eq("[REDACTED]")
      expect(out["response"]).to eq("[REDACTED]")
    end

    it "leaves metadata fields intact" do
      payload = { "model" => "llama3", "prompt_eval_count" => 10 }
      out = described_class.call(payload)
      expect(out["model"]).to eq("llama3")
      expect(out["prompt_eval_count"]).to eq(10)
    end
  end
end
