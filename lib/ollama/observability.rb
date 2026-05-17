# frozen_string_literal: true

require_relative "observability/version"
require_relative "observability/instrumentor"

module Ollama
  module Observability
    class Error < StandardError; end
  end
end
