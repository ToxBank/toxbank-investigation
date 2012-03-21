require File.join(File.expand_path(File.dirname(__FILE__)),"setup.rb")

class UploadTest < Test::Unit::TestCase

  def setup
  end
  
  def teardown
  end
  
  def test_01_basic_response
    response = `curl -i --user #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} '#{FOUR_STORE}/status/'`.chomp
    assert_match /200/, response
  end
  
  def test_02_add_data
    # upload invalid data
    response = `curl -0 -i -u guest:toxbank -T '#{File.join File.dirname(__FILE__),"data/invalid/BII-invalid.n3"}' '#{FOUR_STORE}/data/BII-I-1.n3'`.chomp
    assert_match /400/, response
    # upload valid data
    response = `curl -0 -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -T '#{File.join File.dirname(__FILE__),"data/valid/BII-I-1.n3"}' '#{FOUR_STORE}/data/BII-I-1.n3'`.chomp
    assert_match /201/, response
  end
  
  def test_03_query_all
    response = `curl -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /500/, response
    response = `curl -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -d "query=SELECT * WHERE {?s ?p ?o} LIMIT 10" '#{FOUR_STORE}/sparql/'`.chomp
    assert_match /200/, response
  end
  
  def test_04_delete_data
    response = `curl -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -X DELETE '#{FOUR_STORE}/data/BII-I-1.n3'`.chomp
    assert_match /200/, response
  end
  
  def test_05_simultaneous_uploads 
    threads = []
    5.times do |t|
      threads << Thread.new(t) do |up|
        #puts "Start Time >> " << (Time.now).to_s
        response = `curl -0 -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -T '#{File.join File.dirname(__FILE__),"data/valid/BII-I-1.n3"}' '#{FOUR_STORE}/data/test#{t}.n3'`.chomp
        assert_match /201/, response
      end
    end
    threads.each {|aThread| aThread.join}
  end
  
  def test_06_delete_simultaneous 
    threads = []
    5.times do |t|
      threads << Thread.new(t) do |up|
        #puts "Start Time >> " << (Time.now).to_s
        response = `curl -i -u #{FOUR_STORE_USER}:#{FOUR_STORE_PASS} -X DELETE '#{FOUR_STORE}/data/test#{t}.n3'`.chomp
        assert_match /200/, response
      end
    end
    threads.each {|aThread| aThread.join}
  end

end
