# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluentd-plugin-grepcounter"
  s.version     = "0.1.5"
  s.authors     = ["Naotoshi Seo"]
  s.email       = ["sonots@gmail.com"]
  s.homepage    = "https://github.com/sonots/fluentd-plugin-grepcounter"
  s.summary     = "Fluentd plugin to grep messages and count the number"
  s.description = s.summary

  s.rubyforge_project = "fluentd-plugin-grepcounter"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "fluentd", ['~> 0.11.0']
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "pry"
  s.add_development_dependency "pry-nav"
  s.add_development_dependency 'coveralls'
  # s.add_development_dependency "delorean"
end
