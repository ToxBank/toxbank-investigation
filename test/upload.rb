require 'rubygems'
require 'test/unit'

HOST = "http://ot-dev.in-silico.ch"

class UploadTest < Test::Unit::TestCase
  def test_upload
    uri = `curl -X POST -F file=@data/isa_TB_ACCUTOX.zip;type=application/zip #{HOST}/investigation`
    puts uri
  end
end
