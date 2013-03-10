class Fluent::GrepCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('watchcatcounter', self)

  config_param :count_interval, :time, :default => 5
  config_param :output_tag, :string, :default => 'count'
  config_param :add_tag_prefix, :string, :default => nil
  config_param :input_key, :string
  config_param :regexp, :string
  config_param :exclude, :string, :default => nil
  config_param :threshold, :integer, :default => 1

  attr_accessor :matches
  attr_accessor :last_checked

  def configure(conf)
    super

    @count_interval = @count_interval.to_i
    @threshold = @threshold.to_i
    @input_key = @input_key.to_s
    @regexp = Regexp.compile(@regexp) if @regexp
    @exclude = Regexp.compile(@exclude) if @exclude

    @matches = {}
    @mutex = Mutex.new
  end

  def start
    super
    @watcher = Thread.new(&method(:watcher))
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
  end

  # Called when new line comes. This method actually does not emit
  def emit(tag, es, chain)
    matches ||= []
    # filter out and insert
    es.each do |time,record|
      value = record[@input_key]
      next unless @regexp and @regexp.match(value)
      next if @exclude and @exclude.match(value)
      matches << value
    end
    # thread safe merge
    @matches[tag] ||= []
    @mutex.synchronize { @matches[tag] += matches }

    chain.next
  end

  private

  # thread callback
  def watcher
    # instance variable, and public accessable, for test
    @last_checked = Fluent::Engine.now
    while true
      sleep 0.5
      if Fluent::Engine.now - @last_checked >= @count_interval
        now = Fluent::Engine.now
        flush_emit(now - @last_checked)
        @last_checked = now
      end
    end
  end

  # This method is the real one to emit
  def flush_emit(step)
    time = Fluent::Engine.now
    flushed_matches, @matches = @matches, {}
    flushed_matches.each do |tag, messages|
      output = generate_output(tag, messages)
      tag = @add_tag_prefix ? "#{@add_tag_prefix}.#{tag}" : (@tag ? @tag : tag)
      Fluent::Engine.emit(tag, time, output) if output
    end
  end

  def generate_output(input_tag, messages)
    return nil if messages.size < @threshold
    output = {}
    output['count'] = messages.size
    output['message'] = messages.join("\n")
    output['last_tag'] = input_tag.split(".").last
    output
  end

end
