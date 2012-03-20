require File.join(File.expand_path(File.dirname(__FILE__)),"setup.rb")

class QueryTest < Test::Unit::TestCase

  def test_01_query_all
    res = OpenTox::RestClientWrapper.get(HOST,{}, {:accept => "application/rdf+xml" , :subjectid => @@subjectid})
    assert_match /200/, res
    assert_match /#{HOST}/, res
    # TODO: add more RDF assertions
  end

  def test_02_sparql
    res = OpenTox::RestClientWrapper.get(HOST,{:query => "select * WHERE { ?s ?p ?o } LIMIT 5"}, {:accept => "application/sparql-results+xml" , :subjectid => @@subjectid})
    assert_equal 200, res.code
    assert_match /head/, res
    assert_match /variable/, res
    assert_match /results/, res
    assert_match /binding/, res
  end

=begin
  def test_02_query_investigation
    # TODO: returns empty results (see get /:id in application.rb)
    `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" "#{HOST}"`.chomp.split("\n").each do |uri|
      puts uri
      res = `curl -H "Accept:application/rdf+xml" -H "subjectid:#{@@subjectid}" "#{uri}"`
      puts res
      assert_match /200/, res
    end
  end
=end
  
end
