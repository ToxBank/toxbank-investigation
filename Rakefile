require "bundler/gem_tasks"
require 'bundler'
Bundler.require
Bundler.setup

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/*.rb'] - FileList["test/setup.rb"]
  t.verbose = true
end

desc "Run tests"
task :default => :test
