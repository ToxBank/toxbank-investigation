require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'
require File.join('~/.toxbank/userpass.rb')


class UploadTest < Test::Unit::TestCase

  def setup
  end
  
  def teardown
  end
  
  def test_01_basic_response
    response = `curl -i --user USER:PASS 'http://4store.in-silico.ch/status/'`.chomp
    assert_match /401/, response
    response = `curl -i --user #{USER}:#{PASS} 'http://4store.in-silico.ch/status/'`.chomp
    assert_match /200/, response
  end
  
  def test_02_add_data
    response = `curl -0 -i -u #{USER}:#{PASS} -T data/valid/BII-I-1.n3 'http://4store.in-silico.ch/data/BII-I-1.n3'`.chomp
    assert_match /201/, response
  end
  
  def test_03_query_all
    response = `curl -i -u #{USER}:#{PASS} 'http://4store.in-silico.ch/sparql/'`.chomp
    assert_match /500/, response
    response = `curl -i -u #{USER}:#{PASS} -d "query=SELECT * WHERE {?s ?p ?o} LIMIT 10" 'http://4store.in-silico.ch/sparql/'`.chomp
    assert_match /200/, response
  end
  
  def test_04_delete_data
    response = `curl -i -u #{USER}:#{PASS} -X DELETE 'http://4store.in-silico.ch/data/BII-I-1.n3'`.chomp
    assert_match /200/, response
  end
  
end
