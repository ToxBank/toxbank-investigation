# Author: Denis Gebele
# Description: ruby script to restore a destroyed 4store backend from locally stored toxbank-investigation files
# Date: 07/Nov/2013

SERVICE = "investigation" # for service config file
require File.join '../opentox-client/lib/opentox-client.rb' # maybe adjust the paths here
require File.join '../opentox-server/lib/opentox-server.rb'

# collect the investigations
investigations = []
Dir.foreach(File.join File.dirname(File.expand_path __FILE__), "investigation") do |inv|
  unless inv =~ /^\./i
    investigations << inv
  end
end

# start restore
puts "\n#{investigations.size} investigations locally stored at the service."
puts "Start upload to backend at #{$four_store[:uri]}."
broken_investigations = ""

investigations.each_with_index do |inv, idx|
  
  if File.exist?(File.join("investigation", inv, inv+".nt"))
    puts "\n========================="
    puts "\nUploading investigation #{idx + 1} with ID #{inv}."
    uri = $investigation[:uri] + inv
    nt = File.join("investigation", inv, inv+".nt")
    OpenTox::Backend::FourStore.put uri, File.read(nt), "application/x-turtle"
    puts "Done."
    
    rdfs = File.join("investigation", inv, "*.rdf")
    Dir.glob(rdfs).each do |dataset|
      unless File.zero?(dataset)
        puts "Upload Dataset #{dataset}."
        OpenTox::Backend::FourStore.post uri, File.read(dataset), "application/x-turtle"
        puts "Done."
      end
    end
    
    puts "Upload isSummarySearchable flag."
    isSS = File.join("investigation", inv, "isSummarySearchable.nt")
    OpenTox::Backend::FourStore.post uri, File.read(isSS), "application/x-turtle"
    puts "Done."
    
    puts "Upload isPublished flag."
    isP = File.join("investigation", inv, "isPublished.nt")
    OpenTox::Backend::FourStore.post uri, File.read(isP), "application/x-turtle"
    puts "Done."

    puts "Update last modified date entry."
    mod = File.join("investigation", inv, "modified.nt")
    x = IO.read(mod)
    # delete all previous entries from OpenTox::Backend::FourStore methods and add date from file
    OpenTox::Backend::FourStore.update "WITH <#{uri}>
    DELETE { <#{uri}> <#{RDF::DC.modified}> ?o} WHERE {<#{uri}> <#{RDF::DC.modified}> ?o};
    INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::DC.modified}> #{x.split(">").last.strip}}}"
    puts "Done.\n"
  else
    broken_investigations << "#{File.join("investigation", inv)}\n"
  end

end

puts "Following broken investigations will be deleted."
puts broken_investigations

if broken_investigations != ""
  broken_investigations.split("\n").each do |broken|
    `rm -rf #{broken}`
    `git commit -am 'removed broken investigation'`
  end
end

