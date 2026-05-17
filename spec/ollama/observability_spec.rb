# frozen_string_literal: true

RSpec.describe Ollama::Observability do
  it "has a version number" do
    expect(Ollama::Observability::VERSION).not_to be nil
  end

  describe Ollama::Observability::Instrumentor do
    let(:instrumentor) { described_class.new(logger: Logger.new(IO::NULL)) }
    let(:client) { Ollama::Client.new }

    it "instruments client on_response hook" do
      instrumented = instrumentor.instrument(client)
      expect(instrumented).to eq(client)

      cfg = client.instance_variable_get(:@config)
      expect(cfg.on_response).to respond_to(:call)

      # Trigger hook
      expect {
        cfg.on_response.call({ "model" => "llama3", "prompt_eval_count" => 10, "eval_count" => 20 }, { endpoint: "/api/chat", model: "llama3" })
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
      hooks = instrumentor.instrument_hooks({ on_token: ->(t, l) {} })
      expect(hooks[:on_token]).to respond_to(:call)
      expect { hooks[:on_token].call("token", nil) }.not_to raise_error
    end
  end
end
