# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluent-plugin-grepcounter"
  s.version     = "0.6.0"
  s.authors     = ["Naotoshi Seo"]
  s.email       = ["sonots@gmail.com"]
  s.homepage    = "https://github.com/sonots/fluent-plugin-grepcounter"
  s.summary     = "Fluentd plugin to count the number of matched messages, and emit if exceeds the threshold"
  s.description = s.summary
  s.licenses    = ["MIT"]

  s.rubyforge_project = "fluent-plugin-grepcounter"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "fluentd"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "rspec-its"
  s.add_development_dependency "pry"
  s.add_development_dependency "pry-nav"
  s.add_development_dependency "coveralls"
  s.add_development_dependency "test-unit", "~> 3.1.5"
end
