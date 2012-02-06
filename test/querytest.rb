require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'

#HOST="http://localhost/"

class QueryTest < Test::Unit::TestCase

  def setup
    info = `4s-size ToxBank`
    response = `curl -X POST -i -F file="@data/valid/BII-I-1.zip;type=application/zip" #{HOST}`.chomp
    assert_match /200/, response
  end

  def teardown
  end
  

  def test_01_get_list_of_investigations    

    response = `curl "http://localhost/"`.chomp 
    uri = response.split("\n").last
    
    # query for all in all investigations
    res = `curl -i -H "Accept:application/sparql-results+json" #{HOST}?query_all=`
    assert_match /200/, res
    assert_match /head/, res
    assert_match /results/, res
    assert_match /bindings/, res
    
    # delete Model in 4store
    del = `4s-delete-model ToxBank #{uri}`  
    # delete Investigation
    response = `curl -i -X DELETE #{uri}`
    puts assert_match /200/, response
    response = `curl -i -H "Accept:text/uri-list" #{uri}`
    puts assert_match /404/, response
    
  end
  
end
