# frozen_string_literal: true

module Ollama
  module Observability
    # Minimal Prometheus text-exposition format exporter.
    #
    # In-memory store of counters and histograms. Call `add_counter`
    # / `observe_histogram` from instrumentation, then call `render` to
    # produce a Prometheus-scrapeable text body.
    class Prometheus
      DEFAULT_BUCKETS = [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000].freeze

      def initialize(buckets: DEFAULT_BUCKETS)
        @buckets = buckets
        @counters = Hash.new { |h, k| h[k] = Hash.new(0) }
        @histograms = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = { count: 0, sum: 0.0, buckets: Hash.new(0) } } }
        @mutex = Mutex.new
      end

      def add_counter(name, value = 1, labels: {})
        @mutex.synchronize { @counters[name][label_key(labels)] += value }
      end

      def observe_histogram(name, value, labels: {})
        @mutex.synchronize do
          entry = @histograms[name][label_key(labels)]
          entry[:count] += 1
          entry[:sum] += value
          @buckets.each { |b| entry[:buckets][b] += 1 if value <= b }
          entry[:buckets][:Inf] += 1
        end
      end

      def render
        @mutex.synchronize do
          out = +""
          @counters.each do |name, by_labels|
            out << "# TYPE #{name} counter\n"
            by_labels.each { |labels, v| out << "#{name}#{format_labels(labels)} #{v}\n" }
          end
          @histograms.each do |name, by_labels|
            out << "# TYPE #{name} histogram\n"
            by_labels.each do |labels, entry|
              @buckets.each do |b|
                out << "#{name}_bucket#{format_labels(labels, le: b.to_s)} #{entry[:buckets][b]}\n"
              end
              out << "#{name}_bucket#{format_labels(labels, le: "+Inf")} #{entry[:buckets][:Inf]}\n"
              out << "#{name}_sum#{format_labels(labels)} #{entry[:sum]}\n"
              out << "#{name}_count#{format_labels(labels)} #{entry[:count]}\n"
            end
          end
          out
        end
      end

      private

      def label_key(labels)
        labels.sort_by { |k, _| k.to_s }.map { |k, v| [k.to_s, v.to_s] }
      end

      def format_labels(labels_kv, extra = {})
        pairs = labels_kv.map { |k, v| %(#{k}="#{v}") }
        extra.each { |k, v| pairs << %(#{k}="#{v}") }
        pairs.empty? ? "" : "{#{pairs.join(",")}}"
      end
    end
  end
end
