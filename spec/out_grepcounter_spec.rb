# encoding: UTF-8
require_relative 'spec_helper'

class Fluent::Test::OutputTestDriver
  def emit_with_tag(record, time=Time.now, tag = nil)
    @tag = tag if tag
    emit(record, time)
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
      context "lack of requirements" do
        let(:config) { '' }
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
        its(:output_tag) { should be_nil }
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected)
      end
      it { emit }
    end

    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected.merge({
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

    context 'exclude' do
      let(:config) { CONFIG + %[regexp WARN \n exclude favicon] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>2,
          "message"=>[
            "2013/01/13T07:02:13.232645 WARN POST /auth",
            "2013/01/13T07:02:43.632145 WARN POST /login"
          ],
        }))
      end
      it { emit }
    end

    context 'threshold (hit)' do
      let(:config) { CONFIG + %[regexp WARN \n threshold 3] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected.merge({
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

    context 'threshold (miss)' do
      let(:config) { CONFIG + %[regexp WARN \n threshold 4] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_not_receive(:emit)
      end
      it { emit }
    end

    context 'output_tag' do
      let(:config) { CONFIG + %[regexp WARN \n output_tag foo] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo", time, expected.merge({
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

    context 'add_tag_prefix' do
      let(:config) { CONFIG + %[regexp WARN \n add_tag_prefix foo] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo.#{tag}", time, expected.merge({
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

    context 'output_with_joined_delimiter' do
      # \\n shall be \n in config file
      let(:config) { CONFIG + %[regexp WARN \n output_with_joined_delimiter \\n] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected.merge({
          "count"=>3, 
          "message"=>"2013/01/13T07:02:13.232645 WARN POST /auth\\n2013/01/13T07:02:21.542145 WARN GET /favicon.ico\\n2013/01/13T07:02:43.632145 WARN POST /login",
        }))
      end
      it { emit }
    end

    context 'aggregate all' do
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar2') } }
        driver.instance.flush_emit(0)
      end

      let(:config) { CONFIG + %[regexp WARN \n aggregate all \n output_tag count] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {
          "count"=>3*2,
          "message"=>[
            "2013/01/13T07:02:13.232645 WARN POST /auth",
            "2013/01/13T07:02:21.542145 WARN GET /favicon.ico",
            "2013/01/13T07:02:43.632145 WARN POST /login"
          ]*2,
        })
      end
      it { emit }
    end

    context 'replace_invalid_sequence' do
      let(:config) { CONFIG + %[regexp WARN \n replace_invalid_sequence true] }
      let(:messages) { [ "\xff".force_encoding('UTF-8') ] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
      end
      it { expect { emit }.not_to raise_error }
    end

    describe "comparator <=" do
      context 'threshold (hit)' do
        let(:config) { CONFIG + %[regexp WARN \n threshold 3 \n comparator <=] }
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, expected.merge({
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

      context 'threshold (miss)' do
        let(:config) { CONFIG + %[regexp WARN \n threshold 2 \n comparator <=] }
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_not_receive(:emit)
        end
        it { emit }
      end
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

        loaded_counts.should == stored_counts
        loaded_matches.should == stored_matches
        loaded_saved_at.should == stored_saved_at
        loaded_saved_duration.should == stored_saved_duration
      end
    end

  end
end
