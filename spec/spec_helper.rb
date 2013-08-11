# encoding: UTF-8
require 'rubygems'
require 'bundler'
Bundler.setup(:default, :test)
Bundler.require(:default, :test)

require 'coveralls'
Coveralls.wear!

require 'rspec'
require 'pry'
require 'fluentd/plugin_spec_helper'
require 'fluentd/plugin/filter_grepcounter'
