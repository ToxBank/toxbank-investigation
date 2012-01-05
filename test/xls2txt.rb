require 'rubygems'
require 'spreadsheet'

Spreadsheet.open(ARGV[0]).worksheets.each do |s|
  File.open("#{s.name}.txt","w+") do |f|
    puts s.rows
    s.each { |r| f.puts r.collect{|c| c.class == Spreadsheet::Formula ? c.value : c}.join("\t") }
  end
end
