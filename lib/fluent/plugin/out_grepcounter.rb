# encoding: UTF-8
require 'fluent/plugin/output'

class Fluent::Plugin::GrepCounterOutput < Fluent::Plugin::Output
  Fluent::Plugin.register_output('grepcounter', self)
  helpers :event_emitter

  # To support log_level option implemented by Fluentd v0.10.43
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  # Define `router` method of v0.12 to support v0.10 or earlier
  unless method_defined?(:router)
    define_method("router") { Fluent::Engine }
  end

  REGEXP_MAX_NUM = 20

  def initialize
    super
    require 'pathname'
  end

  config_param :input_key, :string, :default => nil,
               :desc => <<-DESC
The target field key to grep out.
Use with regexp or exclude.
DESC
  config_param :regexp, :string, :default => nil,
               :desc => 'The filtering regular expression.'
  config_param :exclude, :string, :default => nil,
               :desc => 'The excluding regular expression like grep -v.'
  (1..REGEXP_MAX_NUM).each {|i| config_param :"regexp#{i}", :string, :default => nil }
  (1..REGEXP_MAX_NUM).each {|i| config_param :"exclude#{i}", :string, :default => nil }
  config_param :count_interval, :time, :default => 5,
               :desc => 'The interval time to count in seconds.'
  config_param :threshold, :integer, :default => nil, # not obsolete, though
               :desc => <<-DESC
The threshold number to emit.
Emit if count value >= specified value.
Note that this param is not obsolete.
DESC
  config_param :comparator, :string, :default => '>=' # obsolete
  config_param :less_than, :float, :default => nil,
               :desc => 'Emit if count value is less than (<) specified value.'
  config_param :less_equal, :float, :default => nil,
               :desc => 'Emit if count value is less than or equal to (<=) specified value.'
  config_param :greater_than, :float, :default => nil,
               :desc => 'Emit if count value is greater than (>) specified value.'
  config_param :greater_equal, :float, :default => nil,
               :desc => <<-DESC
This is same with threshold option.
Emit if count value is greater than or equal to (>=) specified value.
DESC
  config_param :output_tag, :string, :default => nil # obsolete
  config_param :tag, :string, :default => nil,
               :desc => 'The output tag. Required for aggregate all.'
  config_param :add_tag_prefix, :string, :default => nil,
               :desc => 'Add tag prefix for output message.'
  config_param :remove_tag_prefix, :string, :default => nil,
               :desc => 'Remove tag prefix for output message.'
  config_param :add_tag_suffix, :string, :default => nil,
               :desc => 'Add tag suffix for output message.'
  config_param :remove_tag_suffix, :string, :default => nil,
               :desc => 'Remove tag suffix for output message.'
  config_param :remove_tag_slice, :string, :default => nil,
               :desc => <<-DESC
Remove tag parts by slice function.
Note that this option behaves like tag.split('.').slice(min..max).
DESC
  config_param :output_with_joined_delimiter, :string, :default => nil # obsolete
  config_param :delimiter, :string, :default => nil,
               :desc => 'Output matched messages after joined with the specified delimiter.'
  config_param :aggregate, :string, :default => 'tag',
               :desc => 'Aggregation unit. One of all, in_tag, out_tag can be specified.'
  config_param :replace_invalid_sequence, :bool, :default => false,
               :desc => "Replace invalid byte sequence in UTF-8 with '?' character if true."
  config_param :store_file, :string, :default => nil,
               :desc => <<-DESC
Store internal count data into a file of the given path on shutdown, and load on statring.
DESC

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

    if conf['@label'].nil? and @tag.nil? and @add_tag_prefix.nil? and @remove_tag_prefix.nil? and @add_tag_suffix.nil? and @remove_tag_suffix.nil? and @remove_tag_slice.nil?
      @add_tag_prefix = 'count' # not ConfigError to support lower version compatibility
    end
    @tag_proc = tag_proc

    case @aggregate
    when 'all'
      raise Fluent::ConfigError, "grepcounter: `tag` must be specified with aggregate all" if @tag.nil?
    when 'tag' # obsolete
      @aggregate = 'in_tag'
    when 'in_tag'
    when 'out_tag'
    else
      raise Fluent::ConfigError, "grepcounter: aggregate allows all/in_tag/out_tag"
    end
    @aggregate_proc = aggregate_proc(@tag_proc)

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
  def process(tag, es)
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

    aggregate_key = @aggregate_proc.call(tag)
    # thread safe merge
    @counts[aggregate_key] ||= 0
    @matches[aggregate_key] ||= []
    @mutex.synchronize do
      @counts[aggregate_key] += count
      @matches[aggregate_key] += matches
    end
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

    case @aggregate
    when 'all'
      count = flushed_counts[:all]
      matches = flushed_matches[:all]
      output = generate_output(count, matches)
      router.emit(@tag, time, output) if output
    when 'out_tag'
      flushed_counts.keys.each do |out_tag|
        count = flushed_counts[out_tag]
        matches = flushed_matches[out_tag]
        output = generate_output(count, matches)
        if output
          router.emit(out_tag, time, output)
        end
      end
    else # in_tag
      flushed_counts.keys.each do |tag|
        count = flushed_counts[tag]
        matches = flushed_matches[tag]
        output = generate_output(count, matches, tag)
        if output
          out_tag = @tag_proc.call(tag)
          router.emit(out_tag, time, output)
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

  def aggregate_proc(tag_proc)
    case @aggregate
    when 'all'
      Proc.new {|tag| :all }
    when 'in_tag'
      Proc.new {|tag| tag }
    when 'out_tag'
      Proc.new {|tag| tag_proc.call(tag) }
    end
  end

  def tag_proc
    tag_slice_proc =
      if @remove_tag_slice
        lindex, rindex = @remove_tag_slice.split('..', 2)
        if lindex.nil? or rindex.nil? or lindex !~ /^-?\d+$/ or rindex !~ /^-?\d+$/
          raise Fluent::ConfigError, "out_grepcounter: remove_tag_slice must be formatted like [num]..[num]"
        end
        l, r = lindex.to_i, rindex.to_i
        Proc.new {|tag| (tags = tag.split('.')[l..r]).nil? ? "" : tags.join('.') }
      else
        Proc.new {|tag| tag }
      end

    rstrip = Proc.new {|str, substr| str.chomp(substr) }
    lstrip = Proc.new {|str, substr| str.start_with?(substr) ? str[substr.size..-1] : str }
    tag_prefix = "#{rstrip.call(@add_tag_prefix, '.')}." if @add_tag_prefix
    tag_suffix = ".#{lstrip.call(@add_tag_suffix, '.')}" if @add_tag_suffix
    tag_prefix_match = "#{rstrip.call(@remove_tag_prefix, '.')}." if @remove_tag_prefix
    tag_suffix_match = ".#{lstrip.call(@remove_tag_suffix, '.')}" if @remove_tag_suffix
    tag_fixed = @tag if @tag
    if tag_prefix_match and tag_suffix_match
      Proc.new {|tag| "#{tag_prefix}#{rstrip.call(lstrip.call(tag_slice_proc.call(tag), tag_prefix_match), tag_suffix_match)}#{tag_suffix}" }
    elsif tag_prefix_match
      Proc.new {|tag| "#{tag_prefix}#{lstrip.call(tag_slice_proc.call(tag), tag_prefix_match)}#{tag_suffix}" }
    elsif tag_suffix_match
      Proc.new {|tag| "#{tag_prefix}#{rstrip.call(tag_slice_proc.call(tag), tag_suffix_match)}#{tag_suffix}" }
    elsif tag_prefix || @remove_tag_slice || tag_suffix
      Proc.new {|tag| "#{tag_prefix}#{tag_slice_proc.call(tag)}#{tag_suffix}" }
    else
      Proc.new {|tag| tag_fixed }
    end
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
