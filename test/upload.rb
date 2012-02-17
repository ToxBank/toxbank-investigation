require 'rubygems'
require File.join(File.dirname(__FILE__),"..","application.rb")
require 'test/unit'
require 'rack/test'

ENV['RACK_ENV'] = 'test'

HOST = "http://localhost/"
AA_SERVER = "https://opensso.in-silico.ch"
TEST_USER = "guest"
TEST_PW = "guest"

class UploadTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def setup
    @tmpdir = File.join(File.dirname(__FILE__),"tmp")
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
  resource = RestClient::Resource.new("#{AA_SERVER}/auth/authenticate")
  @@subjectid = resource.post(:username=>TEST_USER, :password => TEST_PW).sub("token.id=","").sub("\n","")
  end

  def teardown
    #FileUtils.remove_entry_secure @tmpdir
  end

  def app
    Sinatra::Application
  end

=begin
  def test_get_all
    get '/'
    assert last_response.ok?
  end

  def test_invalid_zip_upload
    file = File.join File.dirname(__FILE__), "data/invalid/isa_TB_ACCUTOX.zip"
    post "/", "file" => Rack::Test::UploadedFile.new(file,"application/zip"), :subjectid => @@subjectid
    assert_match /202/, last_response.errors
    uri = last_response.body.chomp
    t = OpenTox::Task.new(uri)
    t.wait_for_completion
    assert_match t.hasStatus, "Error"
  end
=end

  def test_valid_zip_upload

    # upload
    ["BII-I-1.zip","isa-tab-renamed.zip"].each do |f|
      file = File.join File.dirname(__FILE__), "data/valid", f
      #post "/", "file" => Rack::Test::UploadedFile.new(file,"application/zip"), :subjectid => @@subjectid
      response = `curl -X POST -i -F file="@#{file};type=application/zip" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
      assert_match /202/, response
      puts response
      #assert_match /202/, last_response.errors
      #uri = last_response.body.chomp
      uri = response.lines[-1]
      puts uri.to_yaml
      #t = OpenTox::Task.new(uri)
      #t.wait_for_completion
      #assert_match t.hasStatus, "Completed"
      #puts t.to_yaml
      #uri = t.resultURI
=begin
      # get zip file
      #
      #get uri, :subjectid => @@subjectid, :accept => "application/zip"
      #puts last_response.to_yaml
      puts uri
      zip = File.join @tmpdir,"tmp.zip"
      puts "curl -H 'Accept:application/zip' -H 'subjectid:#{@@subjectid}' #{uri} > #{zip}"
      `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{zip}`
      #File.open(zip,"w+"){|f| f.puts last_response.body}
      `unzip -o #{zip} -d #{@tmpdir}`
      files = `unzip -l data/valid/#{f}|grep txt|cut -c 31- | sed 's#^.*/##'`.split("\n")
      files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

      # get isatab files
      `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`.split("\n").each do |u|
        response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
        # fix UTF-8 encoding
        #if String.method_defined?(:encode) # ruby 1.9
          assert_match /HTTP\/1.1 200 OK/, response.to_s.encode!('UTF-8', 'UTF-8', :invalid => :replace) 
        #else
          #require 'iconv'
          #ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
          #assert_match /HTTP\/1.1 200 OK/, ic.iconv(response.to_s)
        #end
      end

      # delete
      delete uri, :subjectid => @subjectid
      assert last_response.ok?
      get uri, :subjectid => @subjectid
      assert !last_response.ok?
      assert_match /404/, last_response.errors
      #response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
      #assert_match /200/, response
      #response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
      #assert_match /404/, response
=end
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
