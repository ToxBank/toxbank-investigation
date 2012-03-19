require "bundler/gem_tasks"
require 'bundler'
Bundler.require
Bundler.setup

# TODO: pass constants to test files
require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")
# TODO: autostart unicorn??
HOST = "http://localhost:8080"


require 'rake/testtask'
task :setup do
  # setup code
  if AA_SERVER
    resource = RestClient::Resource.new("#{AA_SERVER}/auth/authenticate")
    @@subjectid = resource.post(:username=>TEST_USER, :password => TEST_PW).sub("token.id=","").sub("\n","")
  else
    @@subjectid = ""
  end
end

Rake::TestTask.new do |t|
  t.libs << 'test'
  #t.test_files = FileList['test/upload.rb']
  t.test_files = FileList['test/*.rb']
  t.verbose = true
end

desc "Run tests"
task :default => :test
