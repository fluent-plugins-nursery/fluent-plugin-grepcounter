# encoding: UTF-8
require_relative 'spec_helper'

class Fluent::Test::OutputTestDriver
  def emit_with_tag(record, time=Time.now, tag = nil)
    @tag = tag if tag
    emit(record, time)
  end
end

class Hash
  def delete!(key)
    self.tap {|h| h.delete(key) }
  end
end

describe Fluent::GrepCounterOutput do
  before { Fluent::Test.setup }
  CONFIG = %[
    input_key message
  ]
  let(:tag) { 'syslog.host1' }
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::GrepCounterOutput, tag).configure(config) }

  describe 'test configure' do
    describe 'bad configuration' do
      context 'should not use classic style and new style together' do
        let(:config) { %[input_key message\nregexp1 message foo] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context 'invalid aggregate' do
        let(:config) { CONFIG + %[aggregate foo] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context 'no tag for aggregate all' do
        let(:config) { CONFIG + %[aggregate all] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context 'invalid comparator' do
        let(:config) { CONFIG + %[comparator foo] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end
    end

    describe 'good configuration' do
      subject { driver.instance }

      context "check default" do
        let(:config) { CONFIG }
        its(:input_key) { should == "message" }
        its(:count_interval) { should == 5 }
        its(:regexp) { should be_nil }
        its(:exclude) { should be_nil }
        its(:threshold) { should == 1 }
        its(:comparator) { should == '>=' }
        its(:tag) { should be_nil }
        its(:add_tag_prefix) { should == 'count' }
      end
    end
  end

  describe 'test emit' do
    let(:time) { Time.now.to_i }
    let(:messages) do
      [
        "2013/01/13T07:02:11.124202 INFO GET /ping",
        "2013/01/13T07:02:13.232645 WARN POST /auth",
        "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
        "2013/01/13T07:02:43.632145 WARN POST /login",
      ]
    end
    let(:emit) do
      driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
      driver.instance.flush_emit(0)
    end
    let(:expected) do
      {
        "count"=>4,
        "message"=>[
          "2013/01/13T07:02:11.124202 INFO GET /ping",
          "2013/01/13T07:02:13.232645 WARN POST /auth",
          "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
          "2013/01/13T07:02:43.632145 WARN POST /login",
        ],
        "input_tag" => tag,
        "input_tag_last" => tag.split('.').last,
      }
    end

    context 'default' do
      let(:config) { CONFIG }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>3,
          "message"=>[
            "2013/01/13T07:02:13.232645 WARN POST /auth",
            "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
            "2013/01/13T07:02:43.632145 WARN POST /login"
          ],
        }))
      end
      it { emit }
    end

    context 'regexpN' do
      let(:config) { %[ regexp1 message WARN ] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>3,
        }).delete!('message'))
      end
      it { emit }
    end

    context 'exclude' do
      let(:config) { CONFIG + %[regexp WARN \n exclude favicon] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>2,
          "message"=>[
            "2013/01/13T07:02:13.232645 WARN POST /auth",
            "2013/01/13T07:02:43.632145 WARN POST /login"
          ],
        }))
      end
      it { emit }
    end

    context 'excludeN' do
      let(:config) { %[regexp1 message WARN \n exclude1 message favicon] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>2,
        }).delete!('message'))
      end
      it { emit }
    end

    context "threshold and comparator (obsolete)" do
      context '>= threshold' do
        let(:config) { CONFIG + %[threshold 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not >= threshold' do
        let(:config) { CONFIG + %[threshold 5] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end

      context '<= threshold' do
        let(:config) { CONFIG + %[threshold 4 \n comparator <=] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not <= threshold' do
        let(:config) { CONFIG + %[threshold 3 \n comparator <=] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end
    end

    context "less and greater" do
      context 'greater_equal' do
        let(:config) { CONFIG + %[greater_equal 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not greater_equal' do
        let(:config) { CONFIG + %[greater_equal 5] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end

      context 'greater_than' do
        let(:config) { CONFIG + %[greater_than 3] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not greater_than' do
        let(:config) { CONFIG + %[greater_than 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end

      context 'less_equal' do
        let(:config) { CONFIG + %[less_equal 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not less_equal' do
        let(:config) { CONFIG + %[less_equal 3] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end

      context 'less_than' do
        let(:config) { CONFIG + %[less_than 5] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not less_than' do
        let(:config) { CONFIG + %[less_than 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end

      context 'between' do
        let(:config) { CONFIG + %[greater_than 1 \n less_than 5] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected)
        end
        it { emit }
      end

      context 'not between' do
        let(:config) { CONFIG + %[greater_than 1 \n less_than 4] }
        before do
          allow(Fluent::Engine).to receive(:now).and_return(time)
          expect(driver.instance.router).not_to receive(:emit)
        end
        it { emit }
      end
    end

    context 'output_tag (obsolete)' do
      let(:config) { CONFIG + %[output_tag foo] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo", time, expected)
      end
      it { emit }
    end

    context 'tag' do
      let(:config) { CONFIG + %[tag foo] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo", time, expected)
      end
      it { emit }
    end

    context 'add_tag_prefix' do
      let(:config) { CONFIG + %[add_tag_prefix foo] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'remove_tag_prefix' do
      let(:config) { CONFIG + %[remove_tag_prefix syslog] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("host1", time, expected)
      end
      it { emit }
    end

    context 'add_tag_suffix' do
      let(:config) { CONFIG + %[add_tag_suffix foo] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("#{tag}.foo", time, expected)
      end
      it { emit }
    end

    context 'remove_tag_suffix' do
      let(:config) { CONFIG + %[remove_tag_suffix host1] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("syslog", time, expected)
      end
      it { emit }
    end

    context 'remove_tag_slice' do
      let(:config) { CONFIG + %[remove_tag_slice 0..-2] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("syslog", time, expected)
      end
      it { emit }
    end

    context 'all tag options' do
      let(:config) { CONFIG + %[
         add_tag_prefix foo
         add_tag_suffix foo
         remove_tag_prefix syslog
         remove_tag_suffix host1
      ]}
      let(:tag) { 'syslog.foo.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo.foo.foo", time, expected)
      end
      it { emit }
    end

    context 'add_tag_prefix.' do
      let(:config) { CONFIG + %[add_tag_prefix foo.] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'remove_tag_prefix.' do
      let(:config) { CONFIG + %[remove_tag_prefix syslog.] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("host1", time, expected)
      end
      it { emit }
    end

    context '.add_tag_suffix' do
      let(:config) { CONFIG + %[add_tag_suffix .foo] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("#{tag}.foo", time, expected)
      end
      it { emit }
    end

    context '.remove_tag_suffix' do
      let(:config) { CONFIG + %[remove_tag_suffix .host1] }
      let(:tag) { 'syslog.host1' }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("syslog", time, expected)
      end
      it { emit }
    end

    context 'output_with_joined_delimiter (obsolete)' do
      # \\n shall be \n in config file
      let(:config) { CONFIG + %[output_with_joined_delimiter \\n] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        message = expected["message"].join('\n')
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge("message" => message))
      end
      it { emit }
    end

    context 'delimiter' do
      # \\n shall be \n in config file
      let(:config) { CONFIG + %[delimiter \\n] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        message = expected["message"].join('\n')
        expect(driver.instance.router).to receive(:emit).with("count.#{tag}", time, expected.merge("message" => message))
      end
      it { emit }
    end

    context 'aggregate all' do
      let(:messages) { ['foobar', 'foobar'] }
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar2') } }
        driver.instance.flush_emit(0)
      end
      let(:expected) do
        {
          "count"=>messages.size*2,
          "message"=>messages*2,
        }
      end

      let(:config) { CONFIG + %[aggregate all \n output_tag count] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("count", time, expected)
      end
      it { emit }
    end

    context 'aggregate in_tag' do
      let(:messages) { ['foobar', 'foobar'] }
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar2') } }
        driver.instance.flush_emit(0)
      end

      let(:config) { CONFIG + %[aggregate tag \n remove_tag_slice 0..-2] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo", time, {
          "count"=>2, "message"=>["foobar", "foobar"], "input_tag"=>"foo.bar", "input_tag_last"=>"bar"
        })
        expect(driver.instance.router).to receive(:emit).with("foo", time, {
          "count"=>2, "message"=>["foobar", "foobar"], "input_tag"=>"foo.bar2", "input_tag_last"=>"bar2"
        })
      end
      it { emit }
    end

    context 'aggregate out_tag' do
      let(:messages) { ['foobar', 'foobar'] }
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar2') } }
        driver.instance.flush_emit(0)
      end

      let(:config) { CONFIG + %[aggregate out_tag \n remove_tag_slice 0..-2] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
        expect(driver.instance.router).to receive(:emit).with("foo", time, {
          "count"=>4, "message"=>["foobar", "foobar", "foobar", "foobar"]
        })
      end
      it { emit }
    end

    context 'replace_invalid_sequence' do
      let(:config) { CONFIG + %[regexp WARN \n replace_invalid_sequence true] }
      let(:messages) { [ "\xff".force_encoding('UTF-8') ] }
      before do
        allow(Fluent::Engine).to receive(:now).and_return(time)
      end
      it { expect { emit }.not_to raise_error }
    end

    describe "store_file" do
      let(:store_file) do
        dirname = "tmp"
        Dir.mkdir dirname unless Dir.exist? dirname
        filename = "#{dirname}/test.dat"
        File.unlink filename if File.exist? filename
        filename
      end

      let(:config) { CONFIG + %[store_file #{store_file}] }

      it 'stored_data and loaded_data should equal' do
        driver.run { messages.each {|message| driver.emit({'message' => message}, time) } }
        driver.instance.shutdown
        stored_counts = driver.instance.counts
        stored_matches = driver.instance.matches
        stored_saved_at = driver.instance.saved_at
        stored_saved_duration = driver.instance.saved_duration
        driver.instance.counts = {}
        driver.instance.matches = {}
        driver.instance.saved_at = nil
        driver.instance.saved_duration = nil

        driver.instance.start
        loaded_counts = driver.instance.counts
        loaded_matches = driver.instance.matches
        loaded_saved_at = driver.instance.saved_at
        loaded_saved_duration = driver.instance.saved_duration

        expect(loaded_counts).to eql(stored_counts)
        expect(loaded_matches).to eql(stored_matches)
        expect(loaded_saved_at).to eql(stored_saved_at)
        expect(loaded_saved_duration).to eql(stored_saved_duration)
      end
    end

  end
end
