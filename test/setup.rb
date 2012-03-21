require 'test/unit'
require 'bundler'
Bundler.require
require 'opentox-client'
require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")

HOST = "http://localhost:8080"
=begin
if defined? AA
  # TODO: move to RestClientWrapper
  resource = RestClient::Resource.new("#{AA}/auth/authenticate")
  @@subjectid = resource.post(:username=>AA_USER, :password => AA_PASS).sub("token.id=","").sub("\n","")
else
  @@subjectid = ""
end
=end
@@subjectid = ""
