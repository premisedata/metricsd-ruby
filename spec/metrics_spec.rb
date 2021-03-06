require 'helper'

describe Metrics do
  class Metrics
    public :socket
  end

  before do
    @metrics = Metrics.new('localhost', 1234)
    @socket = Thread.current[:metricsd_socket] = FakeUDPSocket.new
  end

  after { Thread.current[:metricsd_socket] = nil }

  describe "#initialize" do
    it "should set the host and port" do
      @metrics.host.must_equal 'localhost'
      @metrics.port.must_equal 1234
    end

    it "should default the host to 127.0.0.1 and port to 8125" do
      metrics = Metrics.new
      metrics.host.must_equal '127.0.0.1'
      metrics.port.must_equal 8125
    end
  end

  describe "#host and #port" do
    it "should set host and port" do
      @metrics.host = '1.2.3.4'
      @metrics.port = 5678
      @metrics.host.must_equal '1.2.3.4'
      @metrics.port.must_equal 5678
    end

    it "should not resolve hostnames to IPs" do
      @metrics.host = 'localhost'
      @metrics.host.must_equal 'localhost'
    end

    it "should set nil host to default" do
      @metrics.host = nil
      @metrics.host.must_equal '127.0.0.1'
    end

    it "should set nil port to default" do
      @metrics.port = nil
      @metrics.port.must_equal 8125
    end

    it "should allow an IPv6 address" do
      @metrics.host = '::1'
      @metrics.host.must_equal '::1'
    end
  end

  describe "#increment" do
    it "should format the message according to the statsd spec" do
      @metrics.increment('foobar')
      @socket.recv.must_equal ['foobar:1|c']
    end

    describe "with a sample rate" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should format the message according to the statsd spec" do
        @metrics.increment('foobar', 0.5)
        @socket.recv.must_equal ['foobar:1|c|@0.5']
      end
    end
  end

  describe "#decrement" do
    it "should format the message according to the statsd spec" do
      @metrics.decrement('foobar')
      @socket.recv.must_equal ['foobar:-1|c']
    end

    describe "with a sample rate" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should format the message according to the statsd spec" do
        @metrics.decrement('foobar', 0.5)
        @socket.recv.must_equal ['foobar:-1|c|@0.5']
      end
    end
  end

  describe "#gauge" do
    it "should send a message with a 'g' type, per the nearbuy fork" do
      @metrics.gauge('begrutten-suffusion', 536)
      @socket.recv.must_equal ['begrutten-suffusion:536|g']
      @metrics.gauge('begrutten-suffusion', -107)
      @socket.recv.must_equal ['begrutten-suffusion:-107|g']
    end

    describe "with a sample rate" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should format the message according to the statsd spec" do
        @metrics.gauge('begrutten-suffusion', 536, 0.1)
        @socket.recv.must_equal ['begrutten-suffusion:536|g|@0.1']
      end
    end
  end

  describe "#timer" do
    it "should format the message according to the statsd spec" do
      @metrics.timer('foobar', 500)
      @socket.recv.must_equal ['foobar:500|ms']
    end

    describe "with a sample rate" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should format the message according to the statsd spec" do
        @metrics.timer('foobar', 500, 0.5)
        @socket.recv.must_equal ['foobar:500|ms|@0.5']
      end
    end
  end

  describe "#timed" do
    it "should format the message according to the statsd spec" do
      @metrics.timed('foobar') { 'test' }
      @socket.recv.must_equal ['foobar:0|ms']
    end

    it "should return the result of the block" do
      result = @metrics.timed('foobar') { 'test' }
      result.must_equal 'test'
    end

    describe "with a sample rate" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery

      it "should format the message according to the statsd spec" do
        @metrics.timed('foobar', 0.5) { 'test' }
        @socket.recv.must_equal ['foobar:0|ms|@0.5']
      end
    end
  end

  describe "#send_stats" do
    it "should require value to be an Integer or nil" do
      @metrics.send(:send_stats, 'x', 3,   :x) # no error
      @metrics.send(:send_stats, 'x', nil, :x) # no error
      proc { @metrics.send(:send_stats, 'x', 3.14,     :x) }.must_raise ArgumentError
      proc { @metrics.send(:send_stats, 'x', '3',      :x) }.must_raise ArgumentError
      proc { @metrics.send(:send_stats, 'x', true,     :x) }.must_raise ArgumentError
      proc { @metrics.send(:send_stats, 'x', [3],      :x) }.must_raise ArgumentError
      proc { @metrics.send(:send_stats, 'x', {'x'=>3}, :x) }.must_raise ArgumentError
    end
  end

  describe "#sampled" do
    describe "when the sample rate is 1" do
      before { class << @metrics; def rand; raise end; end }
      it "should send" do
        @metrics.timer('foobar', 500, 1)
        @socket.recv.must_equal ['foobar:500|ms']
      end
    end

    describe "when the sample rate is greater than a random value [0,1]" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should send" do
        @metrics.timer('foobar', 500, 0.5)
        @socket.recv.must_equal ['foobar:500|ms|@0.5']
      end
    end

    describe "when the sample rate is less than a random value [0,1]" do
      before { class << @metrics; def rand; 1; end; end } # ensure no delivery
      it "should not send" do
        @metrics.timer('foobar', 500, 0.5).must_equal nil
      end
    end

    describe "when the sample rate is equal to a random value [0,1]" do
      before { class << @metrics; def rand; 0; end; end } # ensure delivery
      it "should send" do
        @metrics.timer('foobar', 500, 0.5)
        @socket.recv.must_equal ['foobar:500|ms|@0.5']
      end
    end
  end

  describe "with namespace" do
    before { @metrics.namespace = 'service' }

    it "should add namespace to increment" do
      @metrics.increment('foobar')
      @socket.recv.must_equal ['service.foobar:1|c']
    end

    it "should add namespace to decrement" do
      @metrics.decrement('foobar')
      @socket.recv.must_equal ['service.foobar:-1|c']
    end

    it "should add namespace to timer" do
      @metrics.timer('foobar', 500)
      @socket.recv.must_equal ['service.foobar:500|ms']
    end

    it "should add namespace to gauge" do
      @metrics.gauge('foobar', 500)
      @socket.recv.must_equal ['service.foobar:500|g']
    end
  end

  describe "with postfix" do
    before { @metrics.postfix = 'ip-23-45-56-78' }

    it "should add postfix to increment" do
      @metrics.increment('foobar')
      @socket.recv.must_equal ['foobar.ip-23-45-56-78:1|c']
    end

    it "should add postfix to decrement" do
      @metrics.decrement('foobar')
      @socket.recv.must_equal ['foobar.ip-23-45-56-78:-1|c']
    end

    it "should add namespace to timer" do
      @metrics.timer('foobar', 500)
      @socket.recv.must_equal ['foobar.ip-23-45-56-78:500|ms']
    end

    it "should add namespace to gauge" do
      @metrics.gauge('foobar', 500)
      @socket.recv.must_equal ['foobar.ip-23-45-56-78:500|g']
    end
  end

  describe '#postfix=' do
    describe "when nil, false, or empty" do
      it "should set postfix to nil" do
        [nil, false, ''].each do |value|
          @metrics.postfix = 'a postfix'
          @metrics.postfix = value
          @metrics.postfix.must_equal nil
        end
      end
    end
  end

  describe "with logging" do
    require 'stringio'
    before { Metrics.logger = Logger.new(@log = StringIO.new)}

    it "should write to the log in debug" do
      Metrics.logger.level = Logger::DEBUG

      @metrics.increment('foobar')

      @log.string.must_match "Metrics: foobar:1|c"
    end

    it "should not write to the log unless debug" do
      Metrics.logger.level = Logger::INFO

      @metrics.increment('foobar')

      @log.string.must_be_empty
    end
  end

  describe "stat names" do
    it "should accept anything as stat" do
      @metrics.increment(Object, 1)
    end

    it "should replace ruby constant delimeter with graphite package name" do
      class Metrics::SomeClass; end
      @metrics.increment(Metrics::SomeClass, 1)

      @socket.recv.must_equal ['Metrics.SomeClass:1|c']
    end

    it "should replace statsd reserved chars in the stat name" do
      @metrics.increment('ray@hostname.blah|blah.blah:blah', 1)
      @socket.recv.must_equal ['ray_hostname.blah_blah.blah_blah:1|c']
    end
  end

  describe "handling socket errors" do
    before do
      require 'stringio'
      Metrics.logger = Logger.new(@log = StringIO.new)
      @socket.instance_eval { def send(*) raise SocketError end }
    end

    it "should ignore socket errors" do
      @metrics.increment('foobar').must_equal nil
    end

    it "should log socket errors" do
      @metrics.increment('foobar')
      @log.string.must_match 'Metrics: SocketError'
    end
  end

  describe "batching" do
    it "should have a default batch size of 10" do
      @metrics.batch_size.must_equal 10
    end

    it "should have a modifiable batch size" do
      @metrics.batch_size = 7
      @metrics.batch_size.must_equal 7
      @metrics.batch do |b|
        b.batch_size.must_equal 7
      end
    end

    it "should flush the batch at the batch size or at the end of the block" do
      @metrics.batch do |b|
        b.batch_size = 3

        # The first three should flush, the next two will be flushed when the
        # block is done.
        5.times { b.increment('foobar') }

        @socket.recv.must_equal [(["foobar:1|c"] * 3).join("\n")]
      end

      @socket.recv.must_equal [(["foobar:1|c"] * 2).join("\n")]
    end

    it "should not flush to the socket if the backlog is empty" do
      batch = Metrics::Batch.new(@metrics)
      batch.flush
      @socket.recv.must_be :nil?

      batch.increment 'foobar'
      batch.flush
      @socket.recv.must_equal %w[foobar:1|c]
    end

    it "should support setting namespace for the underlying instance" do
      batch = Metrics::Batch.new(@metrics)
      batch.namespace = 'ns'
      @metrics.namespace.must_equal 'ns'
    end

    it "should support setting host for the underlying instance" do
      batch = Metrics::Batch.new(@metrics)
      batch.host = '1.2.3.4'
      @metrics.host.must_equal '1.2.3.4'
    end

    it "should support setting port for the underlying instance" do
      batch = Metrics::Batch.new(@metrics)
      batch.port = 42
      @metrics.port.must_equal 42
    end

  end

  describe "thread safety" do

    it "should use a thread local socket" do
      Thread.current[:metricsd_socket].must_equal @socket
      @metrics.send(:socket).must_equal @socket
    end

    it "should create a new socket when used in a new thread" do
      sock = @metrics.send(:socket)
      Thread.new { Thread.current[:metricsd_socket] }.value.wont_equal sock
    end

  end
end

describe Metrics do
  describe "with a real UDP socket" do
    it "should actually send stuff over the socket" do
      Thread.current[:metricsd_socket] = nil
      socket = UDPSocket.new
      host, port = 'localhost', 12345
      socket.bind(host, port)

      metrics = Metrics.new(host, port)
      metrics.increment('foobar')
      message = socket.recvfrom(16).first
      message.must_equal 'foobar:1|c'
    end

    it "should send stuff over an IPv4 socket" do
      Thread.current[:metricsd_socket] = nil
      socket = UDPSocket.new Socket::AF_INET
      host, port = '127.0.0.1', 12346
      socket.bind(host, port)

      metrics = Metrics.new(host, port)
      metrics.increment('foobar')
      message = socket.recvfrom(16).first
      message.must_equal 'foobar:1|c'
    end

    it "should send stuff over an IPv6 socket" do
      Thread.current[:metricsd_socket] = nil
      socket = UDPSocket.new Socket::AF_INET6
      host, port = '::1', 12347
      socket.bind(host, port)

      metrics = Metrics.new(host, port)
      metrics.increment('foobar')
      message = socket.recvfrom(16).first
      message.must_equal 'foobar:1|c'
    end
  end
end if ENV['LIVE']
