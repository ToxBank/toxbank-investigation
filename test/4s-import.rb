require 'rubygems'
require 'fileutils'
require 'test/unit'
require 'uri'

class ImportTest < Test::Unit::TestCase

  def setup
    @file = File.join('~/toxbank-investigation/test/data/file88.rdf')
    @tmpdir = "./tmp"
    FileUtils.mkdir_p @tmpdir
    @cmd = `4s-import -v ToxBank #{@file}`
  end

  def teardown
    FileUtils.remove_entry_secure @tmpdir
  end

  def test_import_rdf
    begin
      orig_std_out = STDOUT.clone
      file = STDOUT.reopen(File.open("#{@tmpdir}/test_import.txt", "w+"))
      p @cmd
      STDOUT.reopen(orig_std_out)
    end
    begin
      lines = IO.readlines("#{@tmpdir}/test_import.txt", "r")
      f = File.readlines("#{@tmpdir}/test_import.txt")
      assert_match /Imported */, f.last
    end
  end
end
