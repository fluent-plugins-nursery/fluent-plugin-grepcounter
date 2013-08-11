# encoding: UTF-8
class Fluentd::Plugin::GrepCounterFilter < Fluentd::Plugin::Filter
  Fluentd::Plugin.register_filter('grepcounter', self)

  config_param :input_key, :string
  config_param :regexp, :string, :default => nil
  config_param :count_interval, :time, :default => 5
  config_param :exclude, :string, :default => nil
  config_param :threshold, :integer, :default => 1
  config_param :comparator, :string, :default => '>='
  config_param :output_tag, :string, :default => nil
  config_param :add_tag_prefix, :string, :default => 'count'
  config_param :output_with_joined_delimiter, :string, :default => nil
  config_param :aggregate, :string, :default => 'tag'
  config_param :replace_invalid_sequence, :bool, :default => false

  attr_accessor :matches
  attr_accessor :last_checked

  def configure(conf)
    super

    @count_interval = @count_interval.to_i
    @input_key = @input_key.to_s
    @regexp = Regexp.compile(@regexp) if @regexp
    @exclude = Regexp.compile(@exclude) if @exclude
    @threshold = @threshold.to_i

    unless ['>=', '<='].include?(@comparator)
      raise Fluentd::ConfigError, "grepcounter: comparator allows >=, <="
    end

    unless ['tag', 'all'].include?(@aggregate)
      raise Fluentd::ConfigError, "grepcounter: aggregate allows tag/all"
    end

    case @aggregate
    when 'all'
      raise Fluentd::ConfigError, "grepcounter: output_tag must be specified with aggregate all" if @output_tag.nil?
    when 'tag'
      # raise Fluentd::ConfigError, "grepcounter: add_tag_prefix must be specified with aggregate tag" if @add_tag_prefix.nil?
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
  def emits(tag, es)
    count = 0; matches = []
    # filter out and insert
    es.each {|time,record|
      handle_error(tag, time, record) {
        value = record[@input_key]
        next unless match(value.to_s)
        matches << value
        count += 1
      }
    }
    # thread safe merge
    @counts[tag] ||= 0
    @matches[tag] ||= []
    @mutex.synchronize do
      @counts[tag] += count
      @matches[tag] += matches
    end
  rescue => e
    log.warn "grepcounter: #{e.class} #{e.message} #{e.backtrace.first}"
  end

  # empty implementation to avoid NoImplementationError
  def emit(tag, time, record)
  end

  # thread callback
  def watcher
    # instance variable, and public accessable, for test
    @last_checked = Time.now.to_i
    while true
      sleep 0.5
      begin
        if Time.now.to_i - @last_checked >= @count_interval
          now = Time.now.to_i
          flush_emit(now - @last_checked)
          @last_checked = now
        end
      rescue => e
        log.warn "grepcounter: #{e.class} #{e.message} #{e.backtrace.first}"
      end
    end
  end

  # This method is the real one to emit
  def flush_emit(step)
    time = Time.now.to_i
    flushed_counts, flushed_matches, @counts, @matches = @counts, @matches, {}, {}

    if @aggregate == 'all'
      count = 0; matches = []
      flushed_counts.keys.each do |tag|
        count += flushed_counts[tag]
        matches += flushed_matches[tag]
      end
      output = generate_output(count, matches)
      collector.emit(@output_tag, time, output) if output
    else
      flushed_counts.keys.each do |tag|
        count = flushed_counts[tag]
        matches = flushed_matches[tag]
        output = generate_output(count, matches, tag)
        tag = @output_tag ? @output_tag : "#{@add_tag_prefix}.#{tag}"
        collector.emit(tag, time, output) if output
      end
    end
  end

  def generate_output(count, matches, tag = nil)
    return nil if count.nil?
    return nil if count == 0 # ignore 0 because standby nodes receive no message usually
    return nil unless eval("#{count} #{@comparator} #{@threshold}")
    output = {}
    output['count'] = count
    output['message'] = @output_with_joined_delimiter.nil? ? matches : matches.join(@output_with_joined_delimiter)
    if tag
      output['input_tag'] = tag
      output['input_tag_last'] = tag.split('.').last
    end
    output
  end

  def match(string)
    begin
      return false if @regexp and !@regexp.match(string)
      return false if @exclude and @exclude.match(string)
    rescue ArgumentError => e
      unless e.message.index("invalid byte sequence in") == 0
        raise
      end
      string = replace_invalid_byte(string)
      return false if @regexp and !@regexp.match(string)
      return false if @exclude and @exclude.match(string)
    end
    return true
  end

  def replace_invalid_byte(string)
    replace_options = { invalid: :replace, undef: :replace, replace: '?' }
    original_encoding = string.encoding
    temporal_encoding = (original_encoding == Encoding::UTF_8 ? Encoding::UTF_16BE : Encoding::UTF_8)
    string.encode(temporal_encoding, original_encoding, replace_options).encode(original_encoding)
  end
end
