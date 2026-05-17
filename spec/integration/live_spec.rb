# frozen_string_literal: true

# Live integration: instrument a real chat and check structured log + metrics.
# Excluded by default; run with: INTEGRATION=1 bundle exec rspec spec/integration

require "stringio"
require "json"

RSpec.describe Ollama::Observability::Instrumentor, :integration do
  before do
    reason = IntegrationHelper.skip_reason(requires_chat: true)
    skip(reason) if reason
  end

  let(:sink) { StringIO.new }
  let(:instrumentor) { described_class.new(logger: Logger.new(sink)) }
  let(:client) do
    Ollama::Client.new(config: Ollama::Config.new.tap { |c| c.base_url = IntegrationHelper::OLLAMA_URL })
  end

  it "emits an ollama.inference structured log for a real chat" do
    instrumentor.instrument(client)
    client.chat(model: IntegrationHelper.chat_model, messages: [{ role: "user", content: "Say ok" }])
    log_line = sink.string.lines.find { |l| l.include?("ollama.inference") }
    expect(log_line).not_to be_nil

    payload = JSON.parse(log_line.split(/INFO -- :\s/).last)
    expect(payload["model"]).to eq(IntegrationHelper.chat_model)
    expect(payload["metrics"]["prompt_tokens"]).to be > 0
    expect(payload["metrics"]["completion_tokens"]).to be > 0
  end
end
