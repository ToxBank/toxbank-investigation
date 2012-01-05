require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'

HOST = "http://localhost/investigation"

class UploadTest < Test::Unit::TestCase

  def setup
    @uri = `curl -X POST -F file="@data/isa_TB_ACCUTOX.zip;type=application/zip" #{HOST}`.chomp
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
  end

  def teardown
    puts `curl -X DELETE #{@uri}`
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_zip_upload
    res = `curl -H "Accept:text/uri-list" #{@uri}`
    assert_match /#{HOST}/, @uri
    assert_match /i_Investigation.txt/, res
    study = `curl -H Accept:text/tab-separated-values #{@uri}/s_TB-ACCUTOX-acetaminophen.txt`
    assert_match /BALB\/3T3/, study
  end

  def test_get_single_files
    `curl -H "Accept:text/uri-list" #{@uri}`.split("\n").each do |uri|
      file = `curl -H Accept:text/tab-separated-values #{uri}`
    end
  end

  def test_get_zip_file
    `curl -H "Accept:application/zip" #{@uri} > #{@tmpdir}/tmp.zip`
    `unzip -o #{@tmpdir}/tmp.zip -d #{@tmpdir}`
    @isatab_files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

  end


=begin
  def test_tab_upload
  end

  def test_add_study
  end

  def test_upload_corrupted
  end
=end

end
