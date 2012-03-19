require 'test/unit'
require 'bundler'
Bundler.require
require 'opentox-client'

#TODO: check 4store emtries/errors

require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")
HOST = "http://localhost:8080"
class UploadTest < Test::Unit::TestCase

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
  resource = RestClient::Resource.new("#{AA}/auth/authenticate")
  @@subjectid = resource.post(:username=>AA_USER, :password => AA_PASS).sub("token.id=","").sub("\n","")
  end

  def teardown
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_get_all
    response = `curl -i #{HOST}`
    assert_match /200/, response
  end

  def test_get_inexisting
    response = `curl -H "Accept:text/uri-list" -i -H "subjectid:#{@@subjectid}" #{HOST}/foo`.chomp
    assert_match /404/, response
  end

  def test_valid_zip_upload
    # upload
    ["BII-I-1.zip","isa-tab-renamed.zip"].each do |f|
      file = File.join File.dirname(__FILE__), "data/valid", f
      response = `curl -X POST -i -F file="@#{file};type=application/zip" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
      assert_match /202/, response
      uri = response.split("\n")[-1]
      t = OpenTox::Task.new(uri)
      assert t.running?
      assert_match t.hasStatus, "Running"
      t.wait
      assert t.completed?
      assert_match t.hasStatus, "Completed"
      uri = t.resultURI
      zip = File.join @tmpdir,"tmp.zip"
      #puts "curl -H 'Accept:application/zip' -H 'subjectid:#{@@subjectid}' #{uri} > #{zip}"
      `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{zip}`
      `unzip -o #{zip} -d #{@tmpdir}`
      files = `unzip -l data/valid/#{f}|grep txt|cut -c 31- | sed 's#^.*/##'`.split("\n")
      files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

      # get isatab files
      `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`.split("\n").each do |u|
        unless u.match(/n3$/)
          response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
          assert_match /HTTP\/1.1 200 OK/, response.to_s.encode!('UTF-8', 'UTF-8', :invalid => :replace) 
        end
      end

      # delete
      response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /200/, response
      response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /404/, response
    end
  end

  def test_invalid_zip_upload
    file = File.join File.dirname(__FILE__), "data/invalid/isa_TB_ACCUTOX.zip"
    response = `curl -X POST -i -F file="@#{file};type=application/zip" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    assert_match /202/, response
    uri = response.split("\n")[-1]
    t = OpenTox::Task.new(uri)
    t.wait
    assert_match t.hasStatus, "Error"
    # TODO: check error message
  end

=begin
  def test_rest_client_wrapper
    ["BII-I-1.zip","isa-tab-renamed.zip"].each do |f|
      file = File.join File.dirname(__FILE__), "data/valid", f
      investigation_uri = OpenTox::RestClientWrapper.post HOST, {:file => File.read(file),:name => file}, {:content_type => "application/zip", :subjectid => @@subjectid}
      puts investigation_uri
      zip = File.join @tmpdir,"tmp.zip"
      #puts "curl -H 'Accept:application/zip' -H 'subjectid:#{@@subjectid}' #{uri} > #{zip}"
      `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{zip}`
      `unzip -o #{zip} -d #{@tmpdir}`
      files = `unzip -l data/valid/#{f}|grep txt|cut -c 31- | sed 's#^.*/##'`.split("\n")
      files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

      # get isatab files
      `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`.split("\n").each do |u|
        unless u.match(/n3$/)
          response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
          assert_match /HTTP\/1.1 200 OK/, response.to_s.encode!('UTF-8', 'UTF-8', :invalid => :replace) 
        end
      end

      # delete
      response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /200/, response
      response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /404/, response
    end
  end
=end

=begin
  def test_ruby_api
    ["BII-I-1.zip","isa-tab-renamed.zip"].each do |f|
      file = File.join File.dirname(__FILE__), "data/valid", f
      investigation = OpenTox::Investigation.create HOST, :file => file, :headers => {:content_type => "application/zip", :subjectid => @@subjectid}
      zip = File.join @tmpdir,"tmp.zip"
      #puts "curl -H 'Accept:application/zip' -H 'subjectid:#{@@subjectid}' #{uri} > #{zip}"
      `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{zip}`
      `unzip -o #{zip} -d #{@tmpdir}`
      files = `unzip -l data/valid/#{f}|grep txt|cut -c 31- | sed 's#^.*/##'`.split("\n")
      files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

      # get isatab files
      `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`.split("\n").each do |u|
        unless u.match(/n3$/)
          response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
          assert_match /HTTP\/1.1 200 OK/, response.to_s.encode!('UTF-8', 'UTF-8', :invalid => :replace) 
        end
      end

      # delete
      response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /200/, response
      response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
      assert_match /404/, response
    end
  end
=end

end
