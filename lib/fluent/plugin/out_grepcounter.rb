# encoding: UTF-8
class Fluent::GrepCounterOutput < Fluent::Output
  Fluent::Plugin.register_output('grepcounter', self)

  # To support log_level option implemented by Fluentd v0.10.43
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  REGEXP_MAX_NUM = 20

  def initialize
    super
    require 'pathname'
  end

  config_param :input_key, :string, :default => nil
  config_param :regexp, :string, :default => nil
  config_param :exclude, :string, :default => nil
  (1..REGEXP_MAX_NUM).each {|i| config_param :"regexp#{i}",  :string, :default => nil }
  (1..REGEXP_MAX_NUM).each {|i| config_param :"exclude#{i}", :string, :default => nil }
  config_param :count_interval, :time, :default => 5
  config_param :threshold, :integer, :default => nil # not obsolete, though
  config_param :comparator, :string, :default => '>=' # obsolete
  config_param :less_than, :float, :default => nil
  config_param :less_equal, :float, :default => nil
  config_param :greater_than, :float, :default => nil
  config_param :greater_equal, :float, :default => nil
  config_param :output_tag, :string, :default => nil # obsolete
  config_param :tag, :string, :default => nil
  config_param :add_tag_prefix, :string, :default => nil
  config_param :remove_tag_prefix, :string, :default => nil
  config_param :add_tag_suffix, :string, :default => nil
  config_param :remove_tag_suffix, :string, :default => nil
  config_param :output_with_joined_delimiter, :string, :default => nil # obsolete
  config_param :delimiter, :string, :default => nil
  config_param :aggregate, :string, :default => 'tag'
  config_param :replace_invalid_sequence, :bool, :default => false
  config_param :store_file, :string, :default => nil

  attr_accessor :counts
  attr_accessor :matches
  attr_accessor :saved_duration
  attr_accessor :saved_at
  attr_accessor :last_checked

  def configure(conf)
    super

    if @input_key
      @regexp = Regexp.compile(@regexp) if @regexp
      @exclude = Regexp.compile(@exclude) if @exclude
    end

    @regexps = {}
    (1..REGEXP_MAX_NUM).each do |i|
      next unless conf["regexp#{i}"]
      key, regexp = conf["regexp#{i}"].split(/ /, 2)
      raise Fluent::ConfigError, "regexp#{i} does not contain 2 parameters" unless regexp
      raise Fluent::ConfigError, "regexp#{i} contains a duplicated key, #{key}" if @regexps[key]
      @regexps[key] = Regexp.compile(regexp)
    end

    @excludes = {}
    (1..REGEXP_MAX_NUM).each do |i|
      next unless conf["exclude#{i}"]
      key, exclude = conf["exclude#{i}"].split(/ /, 2)
      raise Fluent::ConfigError, "exclude#{i} does not contain 2 parameters" unless exclude
      raise Fluent::ConfigError, "exclude#{i} contains a duplicated key, #{key}" if @excludes[key]
      @excludes[key] = Regexp.compile(exclude)
    end

    if @input_key and (!@regexps.empty? or !@excludes.empty?)
      raise Fluent::ConfigError, "Classic style `input_key`, and new style `regexpN`, `excludeN` can not be used together"
    end

    # to support obsolete options
    @tag ||= @output_tag
    @delimiter ||= @output_with_joined_delimiter

    # to support obsolete `threshold` and `comparator` options
    if @threshold.nil? and @less_than.nil? and @less_equal.nil? and @greater_than.nil? and @greater_equal.nil?
      @threshold = 1
    end
    unless %w[>= <=].include?(@comparator)
      raise Fluent::ConfigError, "grepcounter: comparator allows >=, <="
    end
    if @threshold
      case @comparator
      when '>='
        @greater_equal = @threshold
      else
        @less_equal = @threshold
      end
    end

    if @tag.nil? and @add_tag_prefix.nil? and @remove_tag_prefix.nil? and @add_tag_suffix.nil? and @remove_tag_suffix.nil?
      @add_tag_prefix = 'count' # not ConfigError to support lower version compatibility
    end
    @tag_prefix = "#{@add_tag_prefix}." if @add_tag_prefix
    @tag_suffix = ".#{@add_tag_suffix}" if @add_tag_suffix
    @tag_prefix_match = "#{@remove_tag_prefix}." if @remove_tag_prefix
    @tag_suffix_match = ".#{@remove_tag_suffix}" if @remove_tag_suffix
    @tag_proc =
      if @tag
        Proc.new {|tag| @tag }
      elsif @tag_prefix_match and @tag_suffix_match
        Proc.new {|tag| "#{@tag_prefix}#{rstrip(lstrip(tag, @tag_prefix_match), @tag_suffix_match)}#{@tag_suffix}" }
      elsif @tag_prefix_match
        Proc.new {|tag| "#{@tag_prefix}#{lstrip(tag, @tag_prefix_match)}#{@tag_suffix}" }
      elsif @tag_suffix_match
        Proc.new {|tag| "#{@tag_prefix}#{rstrip(tag, @tag_suffix_match)}#{@tag_suffix}" }
      else
        Proc.new {|tag| "#{@tag_prefix}#{tag}#{@tag_suffix}" }
      end

    case @aggregate
    when 'all'
      raise Fluent::ConfigError, "grepcounter: `tag` must be specified with aggregate all" if @tag.nil?
    when 'tag'
      # raise Fluent::ConfigError, "grepcounter: add_tag_prefix must be specified with aggregate tag" if @add_tag_prefix.nil?
    else
      raise Fluent::ConfigError, "grepcounter: aggregate allows tag/all"
    end

    if @store_file
      f = Pathname.new(@store_file)
      if (f.exist? && !f.writable_real?) || (!f.exist? && !f.parent.writable_real?)
        raise Fluent::ConfigError, "#{@store_file} is not writable"
      end
    end

    @matches = {}
    @counts  = {}
    @mutex = Mutex.new
  end

  def start
    super
    load_status(@store_file, @count_interval) if @store_file
    @watcher = Thread.new(&method(:watcher))
  end

  def shutdown
    super
    @watcher.terminate
    @watcher.join
    save_status(@store_file) if @store_file
  end

  # Called when new line comes. This method actually does not emit
  def emit(tag, es, chain)
    count = 0; matches = []
    # filter out and insert
    es.each do |time,record|
      catch(:break_loop) do
        if key = @input_key
          value = record[key].to_s
          throw :break_loop if @regexp and !match(@regexp, value)
          throw :break_loop if @exclude and match(@exclude, value)
          matches << value # old style stores as an array of values
        else
          @regexps.each do |key, regexp|
            throw :break_loop unless match(regexp, record[key].to_s)
          end
          @excludes.each do |key, exclude|
            throw :break_loop if match(exclude, record[key].to_s)
          end
          matches << record # new style stores as an array of hashes, but how to utilize it?
        end
        count += 1
      end
    end
    # thread safe merge
    @counts[tag] ||= 0
    @matches[tag] ||= []
    @mutex.synchronize do
      @counts[tag] += count
      @matches[tag] += matches
    end

    chain.next
  rescue => e
    log.warn "grepcounter: #{e.class} #{e.message} #{e.backtrace.first}"
  end

  # thread callback
  def watcher
    # instance variable, and public accessable, for test
    @last_checked ||= Fluent::Engine.now
    while true
      sleep 0.5
      begin
        if Fluent::Engine.now - @last_checked >= @count_interval
          now = Fluent::Engine.now
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
    time = Fluent::Engine.now
    flushed_counts, flushed_matches, @counts, @matches = @counts, @matches, {}, {}

    if @aggregate == 'all'
      count = 0; matches = []
      flushed_counts.keys.each do |tag|
        count += flushed_counts[tag]
        matches += flushed_matches[tag]
      end
      output = generate_output(count, matches)
      Fluent::Engine.emit(@tag, time, output) if output
    else
      flushed_counts.keys.each do |tag|
        count = flushed_counts[tag]
        matches = flushed_matches[tag]
        output = generate_output(count, matches, tag)
        if output
          emit_tag = @tag_proc.call(tag)
          Fluent::Engine.emit(emit_tag, time, output)
        end
      end
    end
  end

  def generate_output(count, matches, tag = nil)
    return nil if count.nil?
    return nil if count == 0 # ignore 0 because standby nodes receive no message usually
    return nil if @less_than     and @less_than   <= count
    return nil if @less_equal    and @less_equal  <  count
    return nil if @greater_than  and count <= @greater_than
    return nil if @greater_equal and count <  @greater_equal
    output = {}
    output['count'] = count
    if @input_key
      output['message'] = @delimiter ? matches.join(@delimiter) : matches
    else
      # no 'message' field in the case of regexpN and excludeN
    end
    if tag
      output['input_tag'] = tag
      output['input_tag_last'] = tag.split('.').last
    end
    output
  end

  def rstrip(string, substring)
    string.chomp(substring)
  end

  def lstrip(string, substring)
    string.index(substring) == 0 ? string[substring.size..-1] : string
  end

  def match(regexp, string)
    begin
      return regexp.match(string)
    rescue ArgumentError => e
      raise e unless e.message.index("invalid byte sequence in") == 0
      string = replace_invalid_byte(string)
      retry
    end
    return true
  end

  def replace_invalid_byte(string)
    replace_options = { invalid: :replace, undef: :replace, replace: '?' }
    original_encoding = string.encoding
    temporal_encoding = (original_encoding == Encoding::UTF_8 ? Encoding::UTF_16BE : Encoding::UTF_8)
    string.encode(temporal_encoding, original_encoding, replace_options).encode(original_encoding)
  end

  # Store internal status into a file
  #
  # @param [String] file_path
  def save_status(file_path)
    begin
      Pathname.new(file_path).open('wb') do |f|
        @saved_at = Fluent::Engine.now
        @saved_duration = @saved_at - @last_checked
        Marshal.dump({
          :counts           => @counts,
          :matches          => @matches,
          :saved_at         => @saved_at,
          :saved_duration   => @saved_duration,
          :regexp           => @regexp,
          :exclude          => @exclude,
          :input_key        => @input_key,
        }, f)
      end
    rescue => e
      log.warn "out_grepcounter: Can't write store_file #{e.class} #{e.message}"
    end
  end

  # Load internal status from a file
  #
  # @param [String] file_path
  # @param [Interger] count_interval
  def load_status(file_path, count_interval)
    return unless (f = Pathname.new(file_path)).exist?
    begin
      f.open('rb') do |f|
        stored = Marshal.load(f)
        if stored[:regexp] == @regexp and
          stored[:exclude] == @exclude and
          stored[:input_key]  == @input_key

          if Fluent::Engine.now <= stored[:saved_at] + count_interval
            @counts = stored[:counts]
            @matches = stored[:matches]
            @saved_at = stored[:saved_at]
            @saved_duration = stored[:saved_duration]

            # skip the saved duration to continue counting
            @last_checked = Fluent::Engine.now - @saved_duration
          else
            log.warn "out_grepcounter: stored data is outdated. ignore stored data"
          end
        else
          log.warn "out_grepcounter: configuration param was changed. ignore stored data"
        end
      end
    rescue => e
      log.warn "out_grepcounter: Can't load store_file #{e.class} #{e.message}"
    end
  end

end
