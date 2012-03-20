require File.join(File.expand_path(File.dirname(__FILE__)),"setup.rb")

class QueryTest < Test::Unit::TestCase

  def setup
  end

  def teardown
  end
  

  def test_01_sparql_inall_forall
    ## nigthly
    ##response = `curl -X POST -i -F file="@data/valid/isa_TB_BII.xls;type=application/vnd.ms-excel" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    ## nigthly
    ##assert_match /200/, response 
    res = `curl -H "Accept:application/sparql-results+xml" -H "subjectid:#{@@subjectid}" "#{HOST}?query_all="`
    assert_match /200/, res
    assert_match /head/, res
    assert_match /variable/, res
    assert_match /results/, res
    assert_match /binding/, res
  end

  def test_02_sparql_in_single_investigation_forall
    ## nigthly
    ##res = `curl -H "Accept:application/sparql-results+xml" -H "subjectid:#{@@subjectid}" "#{HOST}0"`
    res = `curl -H "Accept:application/sparql-results+xml" -H "subjectid:#{@@subjectid}" "#{HOST}96"`# <-delete for nightly test
    assert_match /200/, res
    assert_match /head/, res
    assert_match /variable/, res
    assert_match /results/, res
    assert_match /binding/, res
  end

  def test_03_sparql_inall_for_individual_content
    res = `curl -H "Accept:application/sparql-results+xml" -H "subjectid:#{@@subjectid}" "#{HOST}?query=Select * =WHERE =?s?p?o =LIMIT 5"`
    assert_match /200/, res
    assert_match /head/, res
    assert_match /variable/, res
    assert_match /results/, res
    assert_match /binding/, res
    ## nigthly
    ##res = `curl "http://localhost/?subjectid=#{CGI.escape(@@subjectid)}"`.chomp
    ##uri = response.split("\n").first
    ## nigthly
    ##response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
    ##puts assert_match /200/, response
  end
  
end
