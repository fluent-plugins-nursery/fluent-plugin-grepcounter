# encoding: UTF-8
require_relative 'spec_helper'
include Fluentd::PluginSpecHelper

module Fluentd::PluginSpecHelper::GrepCounterFilter
  # Create the GrepCounterFilter Plugin TestDriver
  # let(:config)
  def create_driver
    generate_driver(Fluentd::Plugin::GrepCounterFilter, config)
  end

  # Emit messages and receive events (outputs)
  # @param driver [PluginDriver] TestDriver
  # @return output events
  # let(:tag)
  # let(:time)
  # let(:messages)
  def emit(driver = create_driver)
    es = Fluentd::MultiEventCollection.new
    messages.each {|message| es.add(time, message) }
    driver.run do |d|
      d.with(tag, time) do |d|
        d.pitches(es)
      end
    end
    driver.instance.flush_emit(1)
    driver.events
  end
end

describe Fluentd::Plugin::GrepCounterFilter do
  include Fluentd::PluginSpecHelper::GrepCounterFilter

  CONFIG = %[
    input_key message
  ]
  let(:tag) { 'syslog.host1' }

  describe 'test configure' do
    describe 'bad configuration' do
      context "lack of requirements" do
        let(:config) { '' }
        it { expect { create_driver }.to raise_error(Fluentd::ConfigError) }
      end

      context 'invalid aggregate' do
        let(:config) do
          CONFIG + %[
          aggregate foo
          ]
        end
        it { expect { create_driver }.to raise_error(Fluentd::ConfigError) }
      end

      context 'no tag for aggregate all' do
        let(:config) do
          CONFIG + %[
          aggregate all
          ]
        end
        it { expect { create_driver }.to raise_error(Fluentd::ConfigError) }
      end

      context 'invalid comparator' do
        let(:config) do
          CONFIG + %[
          comparator foo
          ]
        end
        it { expect { create_driver }.to raise_error(Fluentd::ConfigError) }
      end
    end

    describe 'good configuration' do
      subject { create_driver.instance }

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

    context 'count_interval' do
      pending
    end

    context 'no grep' do
      let(:config) { CONFIG }
      it 'should pass all messages' do
        record = emit["count.#{tag}"].first.record
        expect(record["count"]).to eql(4)
        expect(record["message"].size).to eql(4)
        expect(record["input_tag"]).to eql(tag)
        expect(record["input_tag_last"]).to eql(tag.split('.').last)
      end
    end

=begin
    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'exclude' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          exclude favicon
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>2,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'threshold (hit)' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          threshold 3
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'threshold (miss)' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          threshold 4
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_not_receive(:emit)
      end
      it { emit }
    end

    context 'output_tag' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          output_tag foo
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("foo", time, {"count"=>3,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'add_tag_prefix' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          add_tag_prefix foo
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("foo.#{tag}", time, {"count"=>3,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'output_with_joined_delimiter' do
      let(:config) do
        # \\n shall be \n in config file
        CONFIG + %[
          regexp WARN
          output_with_joined_delimiter \\n
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3, 
          "message"=>"2013/01/13T07:02:13.232645 WARN POST /auth\\n2013/01/13T07:02:21.542145 WARN GET /favicon.ico\\n2013/01/13T07:02:43.632145 WARN POST /login",
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'aggregate all' do
      let(:emit) do
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar') } }
        driver.run { messages.each {|message| driver.emit_with_tag({'message' => message}, time, 'foo.bar2') } }
        driver.instance.flush_emit(0)
      end

      let(:config) do
        CONFIG + %[
          regexp WARN
          aggregate all
          output_tag count
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
        Fluentd::Plugin::Engine.should_receive(:emit).with("count", time, {"count"=>3*2,
          "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"]*2,
        })
      end
      it { emit }
    end

    context 'replace_invalid_sequence' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          replace_invalid_sequence true
        ]
      end
      let(:messages) do
        [
          "\xff".force_encoding('UTF-8'),
        ]
      end
      before do
        Fluentd::Plugin::Engine.stub(:now).and_return(time)
      end
      it { expect { emit }.not_to raise_error(ArgumentError) }
    end

    describe "comparator <=" do
      context 'threshold (hit)' do
        let(:config) do
          CONFIG + %[
          regexp WARN
          threshold 3
          comparator <=
          ]
        end
        before do
          Fluentd::Plugin::Engine.stub(:now).and_return(time)
          Fluentd::Plugin::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
            "message"=>["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
            "input_tag" => tag,
            "input_tag_last" => tag.split('.').last,
          })
        end
        it { emit }
      end

      context 'threshold (miss)' do
        let(:config) do
          CONFIG + %[
          regexp WARN
          threshold 2
          comparator <=
          ]
        end
        before do
          Fluentd::Plugin::Engine.stub(:now).and_return(time)
          Fluentd::Plugin::Engine.should_not_receive(:emit)
        end
        it { emit }
      end
    end
=end
  end

end



