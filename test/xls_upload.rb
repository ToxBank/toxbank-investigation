require File.join(File.expand_path(File.dirname(__FILE__)),"setup.rb")

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
    file = File.join File.dirname(__FILE__), "data/invalid/isa_TB_ACCUTOX.xls"
    response = `curl -X POST -i -F file="@#{file};type=application/vnd.ms-excel" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    #assert_match /400/, response
    #uri = response.split("\n").last
    assert_match /202/, response
    uri = response.split("\n")[-1]
    t = OpenTox::Task.new(uri)
    t.wait
    assert_match t.hasStatus, "Error"
  end
  
  def test_02_valid_xls_upload
    # upload
    file = File.join File.dirname(__FILE__), "data/valid/isa_TB_BII.xls"
    response = `curl -X POST -i -F file="@#{file};type=application/vnd.ms-excel" -H "subjectid:#{@@subjectid}" #{HOST}`.chomp
    assert_match /202/, response
    uri = response.split("\n")[-1]
    t = OpenTox::Task.new(uri)
    assert t.running?
    t.wait
    assert t.completed?
    uri = t.resultURI
    
    # get zip file
    `curl -H "Accept:application/zip" -H "subjectid:#{@@subjectid}" #{uri} > #{@tmpdir}/tmp.zip`
    `unzip -o #{@tmpdir}/tmp.zip -d #{@tmpdir}`
    @isatab_files.each{|f| assert_equal true, File.exists?(File.join(File.expand_path(@tmpdir),f)) }

    # get isatab files
    `curl -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`.split("\n").each do |u|
      if u.match(/txt$/)
        response = `curl -i -H Accept:text/tab-separated-values -H "subjectid:#{@@subjectid}" #{u}`
        assert_match /200/, response
      end
    end

    # delete
    response = `curl -i -X DELETE -H "subjectid:#{@@subjectid}" #{uri}`
    assert_match /200/, response
    response = `curl -i -H "Accept:text/uri-list" -H "subjectid:#{@@subjectid}" #{uri}`
    assert_match /404/, response
  end
  
end
