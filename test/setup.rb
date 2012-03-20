require 'test/unit'
require 'bundler'
Bundler.require
require 'opentox-client'
require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")

HOST = "http://localhost:8080"
if defined? AA_SERVER
  # TODO: move to RestClientWrapper
  resource = RestClient::Resource.new("#{AA_SERVER}/auth/authenticate")
  @@subjectid = resource.post(:username=>AA_USER, :password => AA_PASS).sub("token.id=","").sub("\n","")
else
  @@subjectid = ""
end

