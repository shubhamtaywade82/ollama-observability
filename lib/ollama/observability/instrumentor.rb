# frozen_string_literal: true

require "ollama_client"
require "opentelemetry/sdk"
require "json"
require "logger"
require "time"

module Ollama
  module Observability
    # Enterprise-grade instrumentation and telemetry layer.
    class Instrumentor
      attr_reader :tracer, :meter, :logger, :redact_payloads

      def initialize(tracer_name: "ollama-client", meter_name: "ollama-client", logger: nil, redact_payloads: true)
        @tracer = OpenTelemetry.tracer_provider.tracer(tracer_name, Ollama::Observability::VERSION)
        @logger = logger || Logger.new($stdout)
        @redact_payloads = redact_payloads

        if OpenTelemetry.respond_to?(:meter_provider)
          @meter = OpenTelemetry.meter_provider.meter(meter_name, Ollama::Observability::VERSION)
          @latency_histogram = @meter.create_histogram("ollama.latency", unit: "ms", description: "Total generation time")
          @ttft_histogram = @meter.create_histogram("ollama.ttft", unit: "ms", description: "Time to first token")
          @prompt_tokens_counter = @meter.create_counter("ollama.tokens.prompt", description: "Prompt tokens evaluated")
          @completion_tokens_counter = @meter.create_counter("ollama.tokens.completion", description: "Completion tokens generated")
          @error_counter = @meter.create_counter("ollama.errors", description: "Ollama operation errors")
        end
      end

      # Instruments an Ollama::Client instance by attaching on_response and stream hooks.
      # @param client [Ollama::Client]
      # @return [Ollama::Client]
      def instrument(client)
        config = client.instance_variable_get(:@config)
        original_hook = config.on_response

        config.on_response = ->(raw, meta) {
          original_hook&.call(raw, meta)
          process_response(raw, meta)
        }

        client
      end

      # Wraps a block with an OpenTelemetry span and error tracking.
      # Useful for manual tracing around client operations or streaming blocks.
      def trace(operation_name, attributes: {})
        start_time = Time.now
        @tracer.in_span(operation_name, attributes: attributes) do |span|
          begin
            yield(span)
          rescue StandardError => e
            @error_counter&.add(1, attributes: { "error.type" => e.class.name })
            span.record_exception(e)
            span.status = OpenTelemetry::Trace::Status.error(e.message)
            raise e
          ensure
            duration = (Time.now - start_time) * 1000.0
            @latency_histogram&.record(duration, attributes: attributes)
          end
        end
      end

      # Helper to wrap streaming hooks with telemetry
      def instrument_hooks(hooks = {}, attributes: {})
        start_time = Time.now
        first_token_time = nil

        original_token = hooks[:on_token]
        original_error = hooks[:on_error]

        hooks[:on_token] = ->(text, logprobs = nil) {
          unless first_token_time
            first_token_time = Time.now
            ttft = (first_token_time - start_time) * 1000.0
            @ttft_histogram&.record(ttft, attributes: attributes)
          end
          original_token&.call(text, logprobs)
        }

        hooks[:on_error] = ->(err) {
          @error_counter&.add(1, attributes: attributes.merge("error.type" => err.class.name))
          original_error&.call(err)
        }

        hooks
      end

      private

      def process_response(raw, meta)
        data = raw.is_a?(String) ? JSON.parse(raw) : raw
        endpoint = meta[:endpoint] || "unknown"
        model = meta[:model] || data["model"] || "unknown"

        prompt_tokens = data["prompt_eval_count"] || 0
        completion_tokens = data["eval_count"] || 0
        total_duration = data["total_duration"] ? data["total_duration"] / 1_000_000.0 : 0.0 # ns to ms
        load_duration = data["load_duration"] ? data["load_duration"] / 1_000_000.0 : 0.0

        attrs = {
          "ollama.model" => model,
          "ollama.endpoint" => endpoint,
          "ollama.finish_reason" => data["done_reason"] || "stop"
        }

        @prompt_tokens_counter&.add(prompt_tokens, attributes: attrs) if prompt_tokens > 0
        @completion_tokens_counter&.add(completion_tokens, attributes: attrs) if completion_tokens > 0
        @latency_histogram&.record(total_duration, attributes: attrs) if total_duration > 0

        # Structured logging
        log_payload = {
          timestamp: Time.now.utc.iso8601,
          event: "ollama.inference",
          model: model,
          endpoint: endpoint,
          metrics: {
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_duration_ms: total_duration.round(2),
            load_duration_ms: load_duration.round(2)
          }
        }

        unless @redact_payloads
          log_payload[:response] = data["response"] || data.dig("message", "content")
        end

        @logger.info(log_payload.to_json)
      rescue StandardError => e
        @logger.error({ event: "ollama.observability.error", error: e.message }.to_json)
      end
    end
  end
end
