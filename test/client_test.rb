# frozen_string_literal: true

require_relative "test_helper"
require "prometheus_exporter/client"

class PrometheusExporterTest < Minitest::Test
  def test_find_the_correct_registered_metric
    client = PrometheusExporter::Client.new

    # register a metrics for testing
    counter_metric = client.register(:counter, "counter_metric", "helping")

    # when the given name doesn't match any existing metric, it returns nil
    result = client.find_registered_metric("not_registered")
    assert_nil(result)

    # when the given name matches an existing metric, it returns this metric
    result = client.find_registered_metric("counter_metric")
    assert_equal(counter_metric, result)

    # when the given name matches an existing metric, but the given type doesn't, it returns nil
    result = client.find_registered_metric("counter_metric", type: :gauge)
    assert_nil(result)

    # when the given name and type match an existing metric, it returns the metric
    result = client.find_registered_metric("counter_metric", type: :counter)
    assert_equal(counter_metric, result)

    # when the given name matches an existing metric, but the given help doesn't, it returns nil
    result = client.find_registered_metric("counter_metric", help: "not helping")
    assert_nil(result)

    # when the given name and help match an existing metric, it returns the metric
    result = client.find_registered_metric("counter_metric", help: "helping")
    assert_equal(counter_metric, result)

    # when the given name matches an existing metric, but the given help and type don't, it returns nil
    result = client.find_registered_metric("counter_metric", type: :gauge, help: "not helping")
    assert_nil(result)

    # when the given name, type, and help all match an existing metric, it returns the metric
    result = client.find_registered_metric("counter_metric", type: :counter, help: "helping")
    assert_equal(counter_metric, result)
  end

  def test_standard_values
    client = PrometheusExporter::Client.new
    counter_metric = client.register(:counter, "counter_metric", "helping")
    assert_equal(false, counter_metric.standard_values("value", "key").has_key?(:opts))

    expected_quantiles = { quantiles: [0.99, 9] }
    summary_metric = client.register(:summary, "summary_metric", "helping", expected_quantiles)
    assert_equal(expected_quantiles, summary_metric.standard_values("value", "key")[:opts])
  end

  def test_close_socket_on_error
    logs = StringIO.new
    logger = Logger.new(logs)
    logger.level = :error

    client =
      PrometheusExporter::Client.new(logger: logger, port: 321, process_queue_once_and_stop: true)
    client.send("put a message in the queue")

    assert_includes(
      logs.string,
      "Prometheus Exporter, failed to send message Connection refused - connect(2) for \"localhost\" port 321",
    )
  end

  def test_overriding_logger
    logs = StringIO.new
    logger = Logger.new(logs)
    logger.level = :warn

    client =
      PrometheusExporter::Client.new(
        logger: logger,
        max_queue_size: 1,
        process_queue_once_and_stop: true,
      )
    client.send("put a message in the queue")
    client.send("put a second message in the queue to trigger the logger")

    assert_includes(logs.string, "dropping message cause queue is full")
  end

  # Regression: gems that monkey-patch TCPSocket.new with a positional-only
  # signature (e.g. socksify, used by httpi/savon for SOAP) misinterpret the
  # `connect_timeout:` keyword as a Hash positional arg and raise
  # `TypeError: no implicit conversion of Hash into String`.
  # When `connect_timeout` is not configured (the default), the client must not
  # pass the keyword argument at all.
  def test_does_not_pass_connect_timeout_kwarg_when_unset
    received_kwargs =
      capture_tcpsocket_new_kwargs do
        PrometheusExporter::Client.new(
          logger: Logger.new(StringIO.new),
          host: "localhost",
          port: 1,
          process_queue_once_and_stop: true,
        ).send("trigger")
      end

    refute_includes(received_kwargs.keys, :connect_timeout)
  end

  def test_passes_connect_timeout_kwarg_when_set
    received_kwargs =
      capture_tcpsocket_new_kwargs do
        PrometheusExporter::Client.new(
          logger: Logger.new(StringIO.new),
          host: "localhost",
          port: 1,
          connect_timeout: 5,
          process_queue_once_and_stop: true,
        ).send("trigger")
      end

    assert_equal(5, received_kwargs[:connect_timeout])
  end

  private

  def capture_tcpsocket_new_kwargs(&block)
    captured = nil
    original = TCPSocket
    Object.send(:remove_const, :TCPSocket)
    Object.const_set(
      :TCPSocket,
      Class.new do
        define_singleton_method(:new) do |*_args, **kwargs|
          captured = kwargs
          raise Errno::ECONNREFUSED, "fake - do not connect"
        end
      end,
    )
    block.call
    captured
  ensure
    Object.send(:remove_const, :TCPSocket)
    Object.const_set(:TCPSocket, original)
  end
end
