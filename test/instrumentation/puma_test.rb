# frozen_string_literal: true

require_relative "../test_helper"
require "prometheus_exporter/instrumentation"

class PrometheusInstrumentationPumaTest < Minitest::Test
  CLUSTER_STATS = {
    "workers" => 2,
    "phase" => 0,
    "booted_workers" => 2,
    "old_workers" => 0,
    "worker_status" => [
      {
        "pid" => 1,
        "index" => 0,
        "phase" => 0,
        "booted" => true,
        "last_status" => {
          "backlog" => 0,
          "running" => 2,
          "pool_capacity" => 5,
          "max_threads" => 5,
          "busy_threads" => 2,
        },
      },
      {
        "pid" => 2,
        "index" => 1,
        "phase" => 0,
        "booted" => true,
        "last_status" => {
          "backlog" => 1,
          "running" => 3,
          "pool_capacity" => 4,
          "max_threads" => 5,
          "busy_threads" => 1,
        },
      },
    ],
  }

  SINGLE_STATS = {
    "backlog" => 0,
    "running" => 1,
    "pool_capacity" => 5,
    "max_threads" => 5,
    "busy_threads" => 1,
  }

  def collector
    @collector ||= PrometheusExporter::Instrumentation::Puma.new
  end

  # Puma <= 6 behavior: Puma.stats returns a JSON-encoded string
  def test_collects_cluster_metrics_when_puma_stats_returns_string
    ::Puma.stub(:stats, JSON.dump(CLUSTER_STATS)) do
      metric = collector.collect
      assert_equal "puma", metric[:type]
      assert_equal 2, metric[:workers]
      assert_equal 2, metric[:booted_workers]
      assert_equal 0, metric[:phase]
      assert_equal 1, metric[:request_backlog]
      assert_equal 5, metric[:running_threads]
      assert_equal 9, metric[:thread_pool_capacity]
      assert_equal 10, metric[:max_threads]
      assert_equal 3, metric[:busy_threads]
    end
  end

  # Puma >= 8 behavior: Puma.stats returns a Hash directly
  def test_collects_cluster_metrics_when_puma_stats_returns_hash
    ::Puma.stub(:stats, CLUSTER_STATS) do
      metric = collector.collect
      assert_equal "puma", metric[:type]
      assert_equal 2, metric[:workers]
      assert_equal 2, metric[:booted_workers]
      assert_equal 0, metric[:phase]
      assert_equal 1, metric[:request_backlog]
      assert_equal 5, metric[:running_threads]
      assert_equal 9, metric[:thread_pool_capacity]
      assert_equal 10, metric[:max_threads]
      assert_equal 3, metric[:busy_threads]
    end
  end

  # Puma >= 8 with symbol-keyed Hash (defensive: handles symbolized keys too)
  def test_collects_cluster_metrics_when_puma_stats_returns_symbol_keyed_hash
    symbolized = JSON.parse(JSON.dump(CLUSTER_STATS), symbolize_names: true)
    ::Puma.stub(:stats, symbolized) do
      metric = collector.collect
      assert_equal 2, metric[:workers]
      assert_equal 1, metric[:request_backlog]
      assert_equal 3, metric[:busy_threads]
    end
  end

  def test_collects_single_mode_metrics_when_puma_stats_returns_string
    ::Puma.stub(:stats, JSON.dump(SINGLE_STATS)) do
      metric = collector.collect
      assert_equal "puma", metric[:type]
      assert_nil metric[:workers]
      assert_equal 0, metric[:request_backlog]
      assert_equal 1, metric[:running_threads]
      assert_equal 5, metric[:thread_pool_capacity]
      assert_equal 5, metric[:max_threads]
      assert_equal 1, metric[:busy_threads]
    end
  end

  def test_collects_single_mode_metrics_when_puma_stats_returns_hash
    ::Puma.stub(:stats, SINGLE_STATS) do
      metric = collector.collect
      assert_equal "puma", metric[:type]
      assert_nil metric[:workers]
      assert_equal 0, metric[:request_backlog]
      assert_equal 1, metric[:running_threads]
      assert_equal 5, metric[:thread_pool_capacity]
      assert_equal 5, metric[:max_threads]
      assert_equal 1, metric[:busy_threads]
    end
  end
end
