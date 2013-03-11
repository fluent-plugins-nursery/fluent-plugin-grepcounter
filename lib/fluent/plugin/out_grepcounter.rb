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
    @counts  = {}
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
    count = 0; matches = []
    # filter out and insert
    es.each do |time,record|
      value = record[@input_key]
      next unless @regexp and @regexp.match(value)
      next if @exclude and @exclude.match(value)
      matches << value if @output_matched_message
      count += 1
    end
    # thread safe merge
    @counts[tag] ||= 0
    @matches[tag] ||= []
    @mutex.synchronize do
      @counts[tag] += count
      @matches[tag] += matches
    end

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
    flushed_counts, flushed_matches, @counts, @matches = @counts, @matches, {}, {}
    flushed_counts.keys.each do |tag|
      count = flushed_counts[tag]
      matches = flushed_matches[tag]
      output = generate_output(tag, count, matches)
      tag = @add_tag_prefix ? "#{@add_tag_prefix}.#{tag}" : @output_tag
      Fluent::Engine.emit(tag, time, output) if output
    end
  end

  def generate_output(input_tag, count, matches)
    return nil if count < @threshold
    output = {}
    output['count'] = count
    output['input_tag'] = input_tag
    output['input_tag_last'] = input_tag.split(".").last
    if @output_matched_message
      output['message'] = @output_with_joined_delimiter.nil? ? matches : matches.join(@output_with_joined_delimiter)
    end
    output
  end

end
