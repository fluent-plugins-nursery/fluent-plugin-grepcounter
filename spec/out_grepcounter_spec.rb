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
        let(:config) do
          CONFIG + %[
          aggregate foo
          ]
        end
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context 'no tag for aggregate all' do
        let(:config) do
          CONFIG + %[
          aggregate all
          ]
        end
        it { expect { driver }.to raise_error(Fluent::ConfigError) }
      end

      context 'invalid comparison' do
        let(:config) do
          CONFIG + %[
          comparison foo
          ]
        end
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
        its(:comparison) { should == '>=' }
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

    context 'count_interval' do
      pending
    end

    context 'default' do
      let(:config) { CONFIG }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>4,
          "message"=>["2013/01/13T07:02:11.124202 INFO GET /ping","2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:21.542145 WARN GET /favicon.ico","2013/01/13T07:02:43.632145 WARN POST /login"],
          "input_tag" => tag,
          "input_tag_last" => tag.split('.').last,
        })
      end
      it { emit }
    end

    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      before do
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>2,
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_not_receive(:emit)
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo", time, {"count"=>3,
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("foo.#{tag}", time, {"count"=>3,
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3, 
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
        Fluent::Engine.stub(:now).and_return(time)
        Fluent::Engine.should_receive(:emit).with("count", time, {"count"=>3*2,
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
        Fluent::Engine.stub(:now).and_return(time)
      end
      it { expect { emit }.not_to raise_error(ArgumentError) }
    end

    describe "comparison <=" do
      context 'threshold (hit)' do
        let(:config) do
          CONFIG + %[
          regexp WARN
          threshold 3
          comparison <=
          ]
        end
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_receive(:emit).with("count.#{tag}", time, {"count"=>3,
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
          comparison <=
          ]
        end
        before do
          Fluent::Engine.stub(:now).and_return(time)
          Fluent::Engine.should_not_receive(:emit)
        end
        it { emit }
      end
    end
  end
end



