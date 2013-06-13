require 'rake'
require 'rspec'
require 'rspec/core/rake_task'
Dir['spec/**/*.rb'].each{|f| require_relative f}

RSpec::Core::RakeTask.new('spec')

task :default => :spec
