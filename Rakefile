require "bundler/gem_tasks"
namespace :isa2rdf do
  desc "Reparse isa-tab files to investigation ntriples file"
  task :reparse do
    # Author: Denis Gebele
    # Description: reparse isatabs with a new isa2rdf version.
    # Date: 07/Mar/2014
 
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
    puts investigations
    
    broken_conversions = ""
    Dir.chdir('java')
    investigations.each_with_index do |inv, idx|
      dir = File.join File.dirname(File.expand_path __FILE__),"investigation",inv
      nt = File.join File.dirname(File.expand_path __FILE__),"investigation", inv, inv+".nt"
      if File.exist?(nt)
        puts "\n========================="
        extrafiles = Dir["#{dir}/*.nt_*"]
        unless extrafiles.nil?
          puts "remove existing extrafiles.\n#{extrafiles}\n"
          extrafiles.each{|file| `rm '#{file}'`}
          puts "Done."
        end
        puts "\nReparse investigation #{idx + 1} with ID #{inv}."
        uri = $investigation[:uri] + '/' + inv
        # reparse
        puts uri
        puts dir
        text = File.read(nt)
        unless text.include?("hasInvType")
          `java -jar -Xmx2048m isa2rdf-cli-1.0.2.jar -d #{dir} -i #{uri} -a #{dir} -o #{nt} -t #{$user_service[:uri]} &`
          id = `grep "#{uri}/I[0-9]" #{File.join nt}|cut -f1 -d ' '`.strip
          `sed -i 's;#{id.split.last};<#{uri}>;g' #{File.join nt}`
          `echo "<#{uri}> <#{RDF.type}> <#{RDF::OT.Investigation}> ." >>  #{File.join nt}`
          puts "Done."
        end
      else
        broken_conversions << "#{inv}\n"
      end
    end
    if broken_conversions != ""
      puts "\nList of broken conversions, stored in 'broken_conversions' file.\n"
      puts broken_conversions
      File.open('broken_conversions', 'w'){ |file| file.write(broken_conversions) }
    end
    Dir.chdir('../investigation')
    `git add -A;git commit -am "updated with isa2rdf v1.0.2"`
    puts "Execute 'rake fourstore:restore' to update local changes in backend !"
  end
end
namespace :fourstore do

  desc "Restore 4store entries from investigation file directory"
  task :restore do
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
    import_errors = ""

    investigations.each_with_index do |inv, idx|
      
      dir = File.join File.dirname(File.expand_path __FILE__),"investigation",inv
      if File.exist?(File.join("investigation", inv, inv+".nt"))
        puts "\n========================="
        puts "\nUploading investigation #{idx + 1} with ID #{inv}."
        uri = $investigation[:uri] + '/' + inv
        nt = File.join("investigation", inv, inv+".nt")
        begin
          OpenTox::Backend::FourStore.put uri, File.read(nt), "text/plain"
          puts "Done."
          
          # extra files
          extrafiles = Dir["#{dir}/*.nt"].reject!{|file| file =~ /#{nt}$|ftpfiles\.nt$|modified\.nt$|isPublished\.nt$|isSummarySearchable\.nt/}
          unless extrafiles.nil?
            extrafiles.each{|dataset| `split -d -l 300000 '#{dataset}' '#{dataset}_'` unless File.zero?(dataset)}
          end
          
          extrafiles = Dir["#{dir}/*.nt_*"]
          unless extrafiles.nil?
            extrafiles.each do |dataset|
              puts "Upload Dataset #{dataset}."
              OpenTox::Backend::FourStore.post uri, File.read(dataset), "text/plain"
              File.delete(dataset)
              puts "Done."
            end
          end
          
          puts "Upload isSummarySearchable flag."
          isSS = File.join("investigation", inv, "isSummarySearchable.nt")
          OpenTox::Backend::FourStore.post uri, File.read(isSS), "text/plain" if File.exist?(isSS)
          puts "Done."
          
          puts "Upload isPublished flag."
          isP = File.join("investigation", inv, "isPublished.nt")
          OpenTox::Backend::FourStore.post uri, File.read(isP), "text/plain" if File.exist?(isP)
          puts "Done."
      
          puts "Upload ftpfiles."
          ftpfiles = File.join("investigation", inv, "ftpfiles.nt")
          OpenTox::Backend::FourStore.post uri, File.read(ftpfiles), "text/plain" if File.exist?(ftpfiles)
          puts "Done."

          puts "Update last modified date entry."
          mod = File.join("investigation", inv, "modified.nt")
          if File.exist?(mod)
            x = IO.read(mod)
            # delete all previous entries from OpenTox::Backend::FourStore methods and add date from file
            OpenTox::Backend::FourStore.update "WITH <#{uri}>
            DELETE { <#{uri}> <#{RDF::DC.modified}> ?o} WHERE {<#{uri}> <#{RDF::DC.modified}> ?o};
            INSERT DATA { GRAPH <#{uri}> {<#{uri}> <#{RDF::DC.modified}> #{x.split(">").last.strip}}}"
            puts "Done.\n"
          end
        rescue
          import_errors << uri
          next
        end
      else
        broken_investigations << "#{File.join("investigation", inv)}\n"
      end
    
    end

    if import_errors != ""
      puts "\nList of investigations with import errors.\n"
      puts import_errors
      File.open('import_errors', 'w'){ |file| file.write(import_errors) }
    end
=begin 
    # remove begin;end block for auto-remove invalid 
    if import_errors != ""
      Dir.chdir('investigation') do
        import_errors.split("\n").each do |errors|
          inv = errors.split("/").last
          # remove from backend
          OpenTox::Backend::FourStore.delete $investigation[:uri] + '/' + inv
          # remove locally
          `rm -rf #{inv};git commit -am 'removed #{inv}'`
        end
      end
    end
=end

    if broken_investigations != ""
      puts "\nList of broken investigations, stored in 'broken_investigations' file.\n"
      puts broken_investigations
      File.open('broken_investigations', 'w'){ |file| file.write(broken_investigations) }
    end

=begin 
    # remove begin;end block for auto-remove invalid
    if broken_investigations != ""
      Dir.chdir('investigation') do
        broken_investigations.split("\n").each do |broken|
          inv = broken.split("/").last
          # remove from backend
          OpenTox::Backend::FourStore.delete $investigation[:uri] + '/' + inv
          # remove locally
          `cd investigation;rm -rf #{inv};git commit -am 'removed #{inv}';cd -`
        end
      end
    end
=end
  end
end
