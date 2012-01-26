require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'

HOST="http://localhost/"

class QueryTest < Test::Unit::TestCase

  def setup
    # check 4store size first
    puts info = `4s-size ToxBank`
    # upload xls file
    response = `curl -X POST -i -F file="@data/valid/isa_TB_BII.xls;type=application/vnd.ms-excel" #{HOST}`.chomp
    assert_match /200/, response
  end

  def teardown
  end
  
  
  def test_01_get_list_of_investigations    
    # list investigations
    response = `curl "http://localhost/?query"`.chomp    
    puts uri = response.split("\n").first
    assert_match /0$/, uri
    
    # check data imported to 4store
    puts info = `4s-size ToxBank`
    
    # delete data in 4store
    puts uri
    puts del = `4s-delete-model ToxBank #{uri}`
    puts info = `4s-size ToxBank`
    
    # delete Investigation
    puts response = `curl -i -X DELETE #{uri}`
    assert_match /200/, response
    response = `curl -i -H "Accept:text/uri-list" #{uri}`
    assert_match /404/, response
    
  end
  
end
