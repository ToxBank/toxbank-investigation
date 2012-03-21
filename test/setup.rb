require 'test/unit'
require 'bundler'
Bundler.require
require 'opentox-client'
require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")

HOST = "http://localhost:8080"
if defined? AA
  @@subjectid = OpenTox::Authorization.authenticate(AA_USER, AA_PASS)
else
  @@subjectid = ""
end
=begin
=end
#@@subjectid = ""
