# encoding: UTF-8
require_relative 'spec_helper'
include Fluentd::PluginSpecHelper

module Fluentd::PluginSpecHelper::GrepCounterFilter
  # Create the GrepCounterFilter Plugin TestDriver
  # let(:config)
  def create_driver(config = config)
    generate_driver(Fluentd::Plugin::GrepCounterFilter, config)
  end

  # Emit messages and receive events (outputs)
  # @param driver [PluginDriver] TestDriver
  # @return output events
  # let(:tag)
  # let(:time)
  # let(:messages)
  def emit(driver = create_driver, tag = tag, time = time, messages = messages)
    es = Fluentd::MultiEventCollection.new
    messages.each {|message| es.add(time, {'message' => message}) }
    driver.run do |d|
      d.with(tag, time) do |d|
        d.pitches(es)
      end
    end
    driver.events
  end

  def flush(driver)
    driver.instance.flush_emit(1)
    driver.events
  end

  def emit_and_flush(driver = create_driver)
    emit(driver)
    flush(driver)
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
        record = emit_and_flush["count.#{tag}"].first.record
        expect(record["count"]).to eql(4)
        expect(record["message"].size).to eql(4)
        expect(record["message"]).to be_kind_of(Array)
        expect(record["input_tag"]).to eql(tag)
        expect(record["input_tag_last"]).to eql(tag.split('.').last)
      end
    end

    context 'regexp' do
      let(:config) { CONFIG + %[ regexp WARN ] }
      it 'should grep WARN' do
        record = emit_and_flush["count.#{tag}"].first.record
        expect(record["count"]).to eql(3)
        expect(record["message"].size).to eql(3)
        expect(record["message"]).to be_kind_of(Array)
        expect(record["input_tag"]).to eql(tag)
        expect(record["input_tag_last"]).to eql(tag.split('.').last)
        record["message"].each {|message| expect(message).to include('WARN') }
      end
    end

    context 'exclude' do
      let(:config) do
        CONFIG + %[
          exclude favicon
        ]
      end
      it 'should exclude favicon' do
        record = emit_and_flush["count.#{tag}"].first.record
        expect(record["count"]).to eql(3)
        expect(record["message"].size).to eql(3)
        expect(record["message"]).to be_kind_of(Array)
        expect(record["input_tag"]).to eql(tag)
        expect(record["input_tag_last"]).to eql(tag.split('.').last)
        record["message"].each {|message| expect(message).not_to include('favicon') }
      end
    end

    context 'threshold (hit)' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          threshold 3
        ]
      end
      it 'should emit' do
        expect(emit_and_flush).to have_key("count.#{tag}")
      end
    end

    context 'threshold (miss)' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          threshold 4
        ]
      end
      it 'should not emit' do
        expect(emit_and_flush).not_to have_key("count.#{tag}")
      end
    end

    context 'output_tag' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          output_tag foo
        ]
      end
      it 'should emit_and_flush with speficied tag' do
        expect(emit_and_flush).to have_key("foo")
      end
    end

    context 'add_tag_prefix' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          add_tag_prefix foo
        ]
      end
      it 'should emit_and_flush by adding specified tag prefix' do
        expect(emit_and_flush).to have_key("foo.#{tag}")
      end
    end

    context 'output_with_joined_delimiter' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          output_with_joined_delimiter "\n"
        ]
      end
      it 'should output with joined delimiter' do
        record = emit_and_flush["count.#{tag}"].first.record
        expect(record["count"]).to eql(3)
        expect(record["message"]).to be_kind_of(String)
        expect(record["input_tag"]).to eql(tag)
        expect(record["input_tag_last"]).to eql(tag.split('.').last)
        expect(record["message"]).to include("\n")
      end
    end

    context 'aggregate all' do
      let(:config) do
        CONFIG + %[
          regexp WARN
          aggregate all
          output_tag count
        ]
      end
      it 'should aggreagate all' do
        driver = create_driver
        emit(driver, 'foo.bar')
        emit(driver, 'foo.bar2')
        record = flush(driver)["count"].first.record
        expect(record["count"]).to eql(3*2)
        expect(record["message"].size).to eql(3*2)
        expect(record["message"]).to be_kind_of(Array)
        record["message"].each {|message| expect(message).to include('WARN') }
      end
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
      it 'should replace invalid byte sequences' do
        expect { emit_and_flush }.not_to raise_error
      end
    end

    describe "comparator <=" do
      context 'threshold (hit)' do
        let(:config) do
          CONFIG + %[
          regexp WARN
          threshold 3
          comparator "<="
          ]
        end
        it 'should emit' do
          expect(emit_and_flush).to have_key("count.#{tag}")
        end
      end

      context 'threshold (miss)' do
        let(:config) do
          CONFIG + %[
          regexp WARN
          threshold 2
          comparator "<="
          ]
        end
        it 'should not emit' do
          expect(emit_and_flush).not_to have_key("count.#{tag}")
        end
      end
    end
  end

end



