require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'rest-client'
require 'uri'

#HOST="http://localhost:4567"

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
    #@test_files = {"data/isa_TB_ACCUTOX.zip" => 400}
  end

  def teardown
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_invalid_zip_upload
    response = `curl -X POST -i -F file="@data/invalid/isa_TB_ACCUTOX.zip;type=application/zip" #{HOST}`.chomp
    assert_match /400 Bad Request/, response
  end

  def test_valid_zip_upload

    # upload
    #["BII-I-1.zip","TB-Accutox.zip"].each do |f|
    ["BII-I-1.zip"].each do |f|
      response = `curl -X POST -i -F file="@data/valid/#{f};type=application/zip" #{HOST}`.chomp
      assert_match /200/, response
      uri = response.split("\n").last

      # get zip file
      `curl -H "Accept:application/zip" #{uri} > #{@tmpdir}/tmp.zip`
      `unzip -o #{@tmpdir}/tmp.zip -d #{@tmpdir}`
      files = `unzip -l data/#{f}|grep txt|cut -c 31- | sed 's#^.*/##'`.split("\n")
      files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

      # get isatab files
      `curl -H "Accept:text/uri-list" #{uri}`.split("\n").each do |u|
        response = `curl -i -H Accept:text/tab-separated-values #{u}`
        # fix UTF-8 encoding
        if String.method_defined?(:encode) # ruby 1.9
          assert_match /HTTP\/1.1 200 OK/, response.to_s.encode!('UTF-8', 'UTF-8', :invalid => :replace) 
        else
          require 'iconv'
          ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
          assert_match /HTTP\/1.1 200 OK/, ic.iconv(response.to_s)
        end
      end

      # delete
      response = `curl -i -X DELETE #{uri}`
      assert_match /200/, response
      response = `curl -i -H "Accept:text/uri-list" #{uri}`
      assert_match /404/, response
    end
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
