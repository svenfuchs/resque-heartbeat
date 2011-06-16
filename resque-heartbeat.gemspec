# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'resque_heartbeat/version'

Gem::Specification.new do |s|
  s.name         = "resque-heartbeat"
  s.version      = ResqueHeartbeat::VERSION
  s.authors      = ["Sven Fuchs"]
  s.email        = "svenfuchs@artweb-design.de"
  s.homepage     = "http://github.com/svenfuchs/resque-heartbeat"
  s.summary      = "[summary]"
  s.description  = "[description]"

  s.files        = `git ls-files app lib`.split("\n")
  s.platform     = Gem::Platform::RUBY
  s.require_path = 'lib'
  s.rubyforge_project = '[none]'

  s.add_dependency 'resque', '~> 1.17.0'
end
