class Fluent::GrepCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('grepcounter', self)

  config_param :input_key, :string
  config_param :regexp, :string
  config_param :count_interval, :time, :default => 5
  config_param :exclude, :string, :default => nil
  config_param :threshold, :integer, :default => 1
  config_param :output_tag, :string, :default => 'count'
  config_param :add_tag_prefix, :string, :default => nil
  config_param :output_matched_message, :bool, :default => false
  config_param :output_with_joined_delimiter, :string, :default => nil

  attr_accessor :matches
  attr_accessor :last_checked

  def configure(conf)
    super

    @count_interval = @count_interval.to_i
    @input_key = @input_key.to_s
    @regexp = Regexp.compile(@regexp) if @regexp
    @exclude = Regexp.compile(@exclude) if @exclude
    @threshold = @threshold.to_i

    if @output_with_joined_delimiter and @output_matched_message == false
      raise Fluent::ConfigError, "'output_matched_message' must be true to use 'output_with_joined_delimiter'"
    end

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
      tag = @add_tag_prefix ? "#{@add_tag_prefix}.#{tag}" : @output_tag
      Fluent::Engine.emit(tag, time, output) if output
    end
  end

  def generate_output(input_tag, messages)
    return nil if messages.size < @threshold
    output = {}
    output['count'] = messages.size
    output['input_tag'] = input_tag
    output['input_tag_last'] = input_tag.split(".").last
    if @output_matched_message
      output['message'] = @output_with_joined_delimiter.nil? ? messages : messages.join(@output_with_joined_delimiter)
    end
    output
  end

end
