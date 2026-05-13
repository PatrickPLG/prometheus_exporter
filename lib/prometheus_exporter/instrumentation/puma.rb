# frozen_string_literal: true

require "json"

# collects stats from puma
module PrometheusExporter::Instrumentation
  class Puma < PeriodicStats
    def self.start(client: nil, frequency: 30, labels: {})
      puma_collector = new(labels)
      client ||= PrometheusExporter::Client.default

      worker_loop do
        metric = puma_collector.collect
        client.send_json metric
      end

      super
    end

    def initialize(metric_labels = {})
      @metric_labels = metric_labels
    end

    def collect
      metric = {
        pid: pid,
        type: "puma",
        hostname: ::PrometheusExporter.hostname,
        metric_labels: @metric_labels,
      }
      collect_puma_stats(metric)
      metric
    end

    def pid
      @pid = ::Process.pid
    end

    def collect_puma_stats(metric)
      # Puma <= 6 returned a JSON string from `Puma.stats`; Puma >= 8 can return
      # a Hash directly (passing a Hash to JSON.parse raises TypeError).
      raw = ::Puma.stats
      stats = raw.is_a?(String) ? JSON.parse(raw) : deep_stringify_keys(raw)

      if stats.key?("workers")
        metric[:phase] = stats["phase"]
        metric[:workers] = stats["workers"]
        metric[:booted_workers] = stats["booted_workers"]
        metric[:old_workers] = stats["old_workers"]

        stats["worker_status"].each do |worker|
          next if worker["last_status"].empty?
          collect_worker_status(metric, worker["last_status"])
        end
      else
        collect_worker_status(metric, stats)
      end
    end

    private

    def deep_stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), out| out[k.to_s] = deep_stringify_keys(v) }
      when Array
        value.map { |v| deep_stringify_keys(v) }
      else
        value
      end
    end

    def collect_worker_status(metric, status)
      metric[:request_backlog] ||= 0
      metric[:running_threads] ||= 0
      metric[:thread_pool_capacity] ||= 0
      metric[:max_threads] ||= 0
      metric[:busy_threads] ||= 0

      metric[:request_backlog] += status["backlog"]
      metric[:running_threads] += status["running"]
      metric[:thread_pool_capacity] += status["pool_capacity"]
      metric[:max_threads] += status["max_threads"]
      metric[:busy_threads] += status["busy_threads"]
    end
  end
end
