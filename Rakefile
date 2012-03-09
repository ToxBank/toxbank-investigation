require "bundler/gem_tasks"
require 'rake/testtask'
require 'bundler'
Bundler.require
require 'opentox-client'
#Bundler.require(:default)
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/upload.rb']
  #t.test_files = FileList['test/*.rb']
  t.verbose = true
end

desc "Run tests"
task :default => :test
