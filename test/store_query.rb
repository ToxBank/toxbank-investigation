require File.join(File.expand_path(File.dirname(__FILE__)),"setup.rb")

class UploadTest < Test::Unit::TestCase

  def setup
  end
  
  def teardown
  end
  
  def test_01_basic_response
    response = `curl -i -k --user #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} '#{FOUR_STORE}/status/'`.chomp
    assert_match /200/, response
    response = `curl -i -k -u guest:guest '#{FOUR_STORE}/status/'`.chomp
    assert_match /401/, response
  end
  
  def test_02_add_data
    # upload invalid data
    response = `curl -0 -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -T '#{File.join File.dirname(__FILE__),"data/invalid/BII-invalid.n3"}' '#{FOUR_STORE}/data/?graph=#{FOUR_STORE}/data/#{FOUR_STORE_USER}/BII-I-1.n3'`.chomp
    assert_match /400/, response
    # upload valid data
    response = `curl -0 -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -T '#{File.join File.dirname(__FILE__),"data/valid/BII-I-1.n3"}' '#{FOUR_STORE}/data/?graph=#{FOUR_STORE}/data/#{FOUR_STORE_USER}/BII-I-1.n3'`.chomp
    assert_match /201/, response
  end
  
  def test_03_query_all
    response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /500/, response
    response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -H 'Accept:application/sparql-results+xml' -d "query=CONSTRUCT { ?s ?p ?o } WHERE {?s ?p ?o} LIMIT 10" '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /200/, response
    assert_match /rdf\:RDF/, response
    assert_match /rdf\:Description/, response
    assert_match /ns0\:hasMember/, response
  end
  
  def test_04_query_sparqle
    response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /500/, response
    response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -H 'Accept:application/sparql-results+xml' -d "query=CONSTRUCT { ?s ?p ?o } FROM <#{FOUR_STORE}/data/#{FOUR_STORE_USER}/BII-I-1.n3> WHERE {?s ?p ?o} LIMIT 10" '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /200/, response
    assert_match /rdf\:RDF/, response
    assert_match /rdf\:Description/, response
    #assert_match /ns0\:hasMember/, response
  end
  
  def test_05_delete_data
    response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -X DELETE '#{FOUR_STORE}/data/?graph=#{FOUR_STORE}/data/#{FOUR_STORE_USER}/BII-I-1.n3'`.chomp
    assert_match /200/, response
  end
=begin  
  def test_06_simultaneous_uploads 
    threads = []
    5.times do |t|
      threads << Thread.new(t) do |up|
        #puts "Start Time >> " << (Time.now).to_s
        response = `curl -0 -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -T '#{File.join File.dirname(__FILE__),"data/valid/BII-I-1.n3"}' '#{FOUR_STORE}/data/?graph=#{FOUR_STORE_USER}/test#{t}.n3'`.chomp
        assert_match /201/, response
      end
    end
    threads.each {|aThread| aThread.join}
  end
  
  def test_07_delete_simultaneous 
    threads = []
    5.times do |t|
      threads << Thread.new(t) do |up|
        #puts "Start Time >> " << (Time.now).to_s
        response = `curl -i -k -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -X DELETE '#{FOUR_STORE}/data/#{FOUR_STORE_USER}/test#{t}.n3'`.chomp
        assert_match /200/, response
      end
    end
    threads.each {|aThread| aThread.join}
  end
=end
end
