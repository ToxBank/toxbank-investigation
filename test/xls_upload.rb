require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'


class UploadTest < Test::Unit::TestCase

  def setup
    @tmpdir = "./tmp"
    FileUtils.mkdir_p @tmpdir
    @isatab_files = [
      "i_Investigation.txt",
      "s_BII-S-1.txt",
      "s_BII-S-2.txt",
      "a_metabolome.txt",
      "a_microarray.txt",
      "a_proteome.txt",
      "a_transcriptome.txt",
    ]
    #@test_files = {"data/isa_TB_ACCUTOX.zip" => 400}
  end

  def teardown
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_01_invalid_xls_upload 
    # upload
    response = `curl -X POST -i -F file="@data/invalid/isa_TB_ACCUTOX.xls;type=application/vnd.ms-excel" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    assert_match /400/, response
    uri = response.split("\n").last
  end
  
  def test_02_valid_xls_upload
    # upload
    response = `curl -X POST -i -F file="@data/valid/isa_TB_BII.xls;type=application/vnd.ms-excel" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    assert_match /200/, response
    uri = response.split("\n").last
    
    # get zip file
    `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{@tmpdir}/tmp.zip`
    `unzip -o #{@tmpdir}/tmp.zip -d #{@tmpdir}`
    @isatab_files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

    # get isatab files
    `curl -H "Accept:text/uri-list" #{uri}`.split("\n").each do |u|
      puts u
      response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
      assert_match /200/, response
    end

    # delete
    response = `curl -i -X DELETE #{uri}`
    assert_match /200/, response
    response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
    assert_match /404/, response
  end
  
end
