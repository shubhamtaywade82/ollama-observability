# frozen_string_literal: true

require_relative "observability/version"
require_relative "observability/log_redactor"
require_relative "observability/prometheus"
require_relative "observability/instrumentor"

module Ollama
  module Observability
    class Error < StandardError; end
  end
end
