require 'rubygems'
require 'rest-client'
require 'test/unit'
require 'uri'


class BasicTest < Test::Unit::TestCase

  # check response from service
  def test_01_get_investigations_200
    response = RestClient.get HOST
    assert_equal 200, response.code
  end

  # check if default response header is text/uri-list 
  def test_02_get_investigations_type
    response = RestClient.get HOST
    assert_equal "text/uri-list", response.headers[:content_type]
  end

  # check sparql query call to all investigations
  def test_03_get_investigations_query
    response = nil
    Net::HTTP.get_response(URI(File.join(HOST, '?query=bla'))) {|http|
      response = http    
    }
    # error response code 501 because it is not implemented jet. 
    assert_equal 501, response.code.to_i
  end

end

class BasicTestCRUDInvestigation < Test::Unit::TestCase

  # check post to investigation service with wrong content type
  def test_01_post_investigation_400
    uri = URI(File.join(HOST, 'investigation'))
    req = Net::HTTP::Post.new(uri.path)
    req.content_type = "text/dummy"
    res = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(req)
    end
    assert_equal 400, res.code.to_i
  end

  # create an investigation by uploading a zip file
  def test_02_post_investigation
    @@uri = ""
    result = `curl -X POST #{HOST} -H "Content-Type: multipart/form-data" -F "file=@data/isa_TB_ACCUTOX.zip;type=application/zip"`
    puts result
    @@uri = URI(result)
    assert @@uri.host == URI(HOST).host
  end

  # get investigation/{id} as text/uri-list
  def test_03_get_investigation_uri_list
    result = RestClient.get @@uri.to_s, :Accept => "text/uri-list"
    assert_equal "text/uri-list", result.headers[:content_type]    
  end

  # get investigation/{id} as application/zip
  def test_04_get_investigation_zip
    result = RestClient.get @@uri.to_s, :Accept => "application/zip"
    assert_equal "application/zip", result.headers[:content_type]    
  end

  # get investigation/{id} as text/tab-separated-values
  def test_05_get_investigation_tab
    result = RestClient.get @@uri.to_s, :Accept => "text/tab-separated-values"
    assert_equal "text/tab-separated-values;charset=utf-8", result.headers[:content_type]    
  end

  # get investigation/{id} as application/sparql-results+json
  def test_06_get_investigation_sparql
    result = RestClient.get @@uri.to_s, :Accept => "application/sparql-results+json" 
    assert_equal "application/sparql-results+json", result.headers[:content_type]    
  end

  # check if uri is in uri-list 
  def test_98_get_investigation
    response = RestClient.get HOST
    assert response.index(@@uri.to_s).class.instance_of?(Fixnum), "URI: #{@@uri} is not in uri-list"
  end

  # delete investigation/{id}
  def test_99_delete_investigation
    result = RestClient.delete @@uri.to_s
    assert result.match(/^investigation.[0-9]*.deleted$/)
  end

end