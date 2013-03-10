# encoding: UTF-8
require_relative 'spec_helper'

describe Fluent::GrepCounterOutput do
  before { Fluent::Test.setup }
  CONFIG = %[
    input_key message
    regexp WARN
  ]
  let(:tag) { 'syslog.host1' }
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::GrepCounterOutput, tag).configure(config) }

  describe 'test configure' do
    describe 'bad configuration' do
      context "lack of requirements" do
        let(:config) { '' }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context "check output_with_joined_delimiter" do
        let(:config) { CONFIG + %[ output_with_joined_delimiter \\n ] }
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end
    end

    describe 'good configuration' do
      subject { driver.instance }

      context "check default" do
        let(:config) { CONFIG }
        its(:input_key) { should == "message" }
        its(:count_interval) { should == 5 }
        its(:regexp) { should == /WARN/ }
        its(:exclude) { should be_nil }
        its(:threshold) { should == 1 }
        its(:output_tag) { should == 'count' }
        its(:add_tag_prefix) { should be_nil }
        its(:output_matched_message) { should be_false }
        its(:output_with_joined_delimiter) { should be_nil }
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

    context 'count_interval' do
      pending
    end

    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {"count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last})
      end
      it { emit }
    end

    context 'exclude' do
      let(:config) do
        CONFIG + %[
          exclude favicon
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {"count"=>2, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last})
      end
      it { emit }
    end

    context 'threshold (less than or equal to)' do
      let(:config) do
        CONFIG + %[
          threshold 3
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {"count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last})
      end
      it { emit }
    end

    context 'threshold (greater)' do
      let(:config) do
        CONFIG + %[
          threshold 4
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_not_receive(:emit)
      end
      it { emit }
    end

    context 'output_tag' do
      let(:config) do
        CONFIG + %[
          output_tag foo
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo", time, {"count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last})
      end
      it { emit }
    end

    context 'add_tag_prefix' do
      let(:config) do
        CONFIG + %[
          add_tag_prefix foo
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo.#{tag}", time, {"count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last})
      end
      it { emit }
    end

    context 'output_matched_message' do
      let(:config) do
        CONFIG + %[
          output_matched_message true
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {
          "count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"]
        })
      end
      it { emit }
    end

    context 'output_with_joined_delimiter' do
      let(:config) do
        # \\n shall be \n in config file
        CONFIG + %[
          output_matched_message true
          output_with_joined_delimiter \\n
        ]
      end
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {
          "count"=>3, "input_tag"=>tag, "input_tag_last"=>tag.split(".").last,
          "message"=>"2013/01/13T07:02:13.232645 WARN POST /auth\\n2013/01/13T07:02:21.542145 WARN GET /favicon.ico\\n2013/01/13T07:02:43.632145 WARN POST /login"
        })
      end
      it { emit }
    end
  end
end



