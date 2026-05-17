# frozen_string_literal: true

module Ollama
  module Observability
    # Redacts user-content payload fields from log dumps while keeping
    # observability metadata (model, token counts, durations, ids) intact.
    module LogRedactor
      REDACTION = "[REDACTED]"
      CONTENT_FIELDS = %w[response content prompt thinking text].freeze

      module_function

      def call(payload)
        case payload
        when Hash
          payload.each_with_object({}) do |(k, v), acc|
            acc[k] = CONTENT_FIELDS.include?(k.to_s) ? REDACTION : call(v)
          end
        when Array
          payload.map { |item| call(item) }
        else
          payload
        end
      end
    end
  end
end
