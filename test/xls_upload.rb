require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'


class UploadTest < Test::Unit::TestCase

  def setup
    #@uri = `curl -X POST -F file="@data/isa_TB_ACCUTOX.zip;type=application/zip" #{HOST}`.chomp
    @tmpdir = "./tmp"
    FileUtils.mkdir_p @tmpdir
    @isatab_files = [
      "i_Investigation.txt",
      "s_TB-ACCUTOX-acetaminophen.txt",
      "a_TB-ACCUTOX-plate1.txt",
      "a_TB-ACCUTOX-plate2.txt",
      "a_TB-ACCUTOX-plate3.txt",
      "acetaminophen-plate1-data.txt",
      "acetaminophen-plate2-data.txt",
      "acetaminophen-plate3-data.txt",
      "ic50.txt",
    ]
    @test_files = {"data/isa_TB_ACCUTOX.zip" => 400}
  end

  def teardown
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_zip_upload
  
    # upload
    response = `curl -X POST -i -F file="@data/isa_TB_ACCUTOX.xls;type=application/vnd.ms-excel" #{HOST}`.chomp
    assert_match /200/, response
    uri = response.split("\n").last
    
    # get zip file
    `curl -H "Accept:application/zip" #{uri} > #{@tmpdir}/tmp.zip`
    `unzip -o #{@tmpdir}/tmp.zip -d #{@tmpdir}`
    @isatab_files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

    # get isatab files
    `curl -H "Accept:text/uri-list" #{uri}`.split("\n").each do |u|
      puts u
      response = `curl -i -H Accept:text/tab-separated-values #{u}`
      assert_match /200/, response
    end

    # delete
    response = `curl -i -X DELETE #{uri}`
    assert_match /200/, response
    response = `curl -i -H "Accept:text/uri-list" #{uri}`
    assert_match /404/, response
  end
end
