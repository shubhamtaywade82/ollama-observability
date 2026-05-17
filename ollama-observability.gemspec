# frozen_string_literal: true

require_relative "lib/ollama/observability/version"

Gem::Specification.new do |spec|
  spec.name = "ollama-observability"
  spec.version = Ollama::Observability::VERSION
  spec.authors = ["Shubham Taywade"]
  spec.email = ["shubhamtaywade82@gmail.com"]

  spec.summary = "Enterprise-grade observability and telemetry layer for Ollama."
  spec.description = "Exposes enterprise-grade metrics, distributed tracing via OpenTelemetry, and structured logging for Ollama inference operations."
  spec.homepage = "https://github.com/ollama-rb/ollama-observability"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ollama-rb/ollama-observability"
  spec.metadata["changelog_uri"] = "https://github.com/ollama-rb/ollama-observability/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ollama-client", "~> 1.3"
  spec.add_dependency "opentelemetry-api", "~> 1.3"
  spec.add_dependency "opentelemetry-sdk", "~> 1.3"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
