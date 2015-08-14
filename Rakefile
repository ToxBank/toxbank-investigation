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
          puts "error"
          import_errors << "#{inv}\n"
          next
        end
      else
        puts "broken"
        broken_investigations << "#{inv}\n"
      end

    end

    if import_errors != ""
      puts "\nList of investigations with import errors:"
      puts "------------------------------------------\n"
      puts import_errors
      File.open('import_errors', 'w'){ |file| file.write(import_errors) }
    end
    puts "\n+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+\n"
    if broken_investigations != ""
      puts "\nList of broken investigations:"
      puts "------------------------------------------\n"
      puts broken_investigations
      File.open('broken_investigations', 'w'){ |file| file.write(broken_investigations) }
      puts "\n"
    end

  end
end

namespace :bioresults do

  SERVICE = "investigation" # for service config file
  require File.join '../opentox-client/lib/opentox-client.rb' # maybe adjust the paths here
  require File.join '../opentox-server/lib/opentox-server.rb'
  require "mongo"

  desc "generating bio search results in json format."
  task :generate do
    # Author: Denis Gebele
    # Description: Generate bio search results in json format.
    # Date: 14/Aug/2015
    
    # collect the investigations
    investigations = []
    Dir.foreach(File.join File.dirname(File.expand_path __FILE__), "investigation") do |inv|
      unless inv =~ /^\./i
        investigations << inv
      end
    end

    # start generating
    puts "\n#{investigations.size} investigations locally stored at the service."
    puts "Start upload to backend at #{$four_store[:uri]}."
    
    investigations.each do |inv|
      dir = File.join File.dirname(File.expand_path __FILE__),"investigation",inv
      investigation_uri = $investigation[:uri] + '/' + inv
      puts dir
      puts investigation_uri
    
      puts "Start processing derived data."
      # locate derived data files and prepare
      # get information about files from assay files by sparql
      datafiles = Dir["#{dir}/*.txt"].each{|file| `dos2unix -k '#{file}'`}
      sparqlstring = File.read(File.join("./template/investigation/files_by_assays.sparql")) % { :investigation_uri => investigation_uri }
      response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
      datafiles = JSON.parse(response)["results"]["bindings"].map{|f| f["file"]["value"]}.uniq
      puts "datafiles: #{datafiles}"
      Mongo::Logger.logger.level = Logger::WARN
      @client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'ToxBank', :connect => :direct)
      my = @client[inv]
      datafiles.delete_if{|file| !File.exists?(File.join(dir,file))}.reject!{|file| file =~ /^i_|^a_|^s_|ftp\:/}
      datafiles.delete_if{|file| `head -n1 '#{File.join(dir,file)}'` !~ /(FC|p-value|q-value)/}
      puts datafiles
      if datafiles.blank?
        puts "No datafiles to process."
      else
        datafiles.each do |file| 
          puts "import file: #{file}"
          `mongoimport -d ToxBank -c #{inv} --ignoreBlanks --type tsv --file '#{File.join(dir, file)}' --headerline` #unless key.blank?
        end 
        # building genelist
        my = @client[inv]
        genelist = []
        symbol = my.find.distinct(:Symbol)
        symbol.each{|x| genelist << "http://onto.toxbank.net/isa/Symbol/#{x}"} unless symbol.blank?
        entrez = my.find.distinct(:Entrez)
        entrez.each{|x| genelist << "http://onto.toxbank.net/isa/Entrez/#{x}"} unless entrez.blank?
        unigene = my.find.distinct(:Unigene)
        unigene.each{|x| genelist << "http://onto.toxbank.net/isa/Unigene/#{x}"} unless unigene.blank?
        refseq = my.find.distinct(:RefSeq)
        refseq.each{|x| genelist << "http://onto.toxbank.net/isa/RefSeq/#{x}"} unless refseq.blank?
        uniprot = my.find.distinct(:Uniprot)
        uniprot.each{|x| genelist << "http://purl.uniprot.org/uniprot/#{x}"} unless uniprot.blank?
        # write to file
        File.open(File.join(dir, "genelist"), 'w') {|f| f.write(genelist.flatten.compact.reject{|g| g.to_s =~ /\/NA$|\/0$/}) }
        #TODO could be more than one assay or study
        assayfiles = Dir["#{dir}/a_*.txt"][0]
        puts assayfiles
        assay = CSV.read(assayfiles, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
        studyfiles = Dir["#{dir}/s_*.txt"][0]
        puts studyfiles
        study = CSV.read(studyfiles, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
        sparqlstring = "SELECT ?title FROM <#{investigation_uri}> WHERE {<#{investigation_uri}> <http://purl.org/dc/terms/title> ?title.} LIMIT 1"
        response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
        @title = JSON.parse(response)["results"]["bindings"].map{|f| f["title"]["value"]}[0]
        genes = genelist.flatten.compact.reject{|g| g.to_s =~ /\/NA$|\/0$/}
        # working with genes
        genes.each do |gene|
          geneclass = (gene =~ /uniprot/i ? gene.split("/")[3].capitalize : gene.split("/")[4])
          gene = gene.split("/").last
          unless File.exists?(File.join(dir, "#{gene}.json"))
            case geneclass
            when "Symbol"
              a = my.find(Symbol: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}}
            when "Uniprot"
              a = my.find(Uniprot: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}}
            when "Unigene"
              a = my.find(Unigene: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}}
            when "RefSeq"
              a = my.find(RefSeq: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}}
            when "Entrez"
              # integer value
              a = my.find(Entrez: gene.to_i).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}}
            else
              bad_request_error "Unknown gene class '#{geneclass}'"
            end
            unless a.to_a[0].blank?
              b = {}
              assay[:data_transformation_name].each_with_index{|name, idx| a.to_a[0].each{|a| (b.has_key?(name) ? b[name] << [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => "#{a[1]}", :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "#{geneclass}:#{gene}", :sample => assay[:sample_name][idx]] : b[name] = [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => "#{a[1]}", :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "#{geneclass}:#{gene}", :sample => assay[:sample_name][idx]]) if a[0] =~ /\b(#{name})\b/ } }
              c = {}
              assay[:sample_name].each{|sample| study.each{|s| factorvalues = {}; s.each_with_index{|e,i| e.each{|y| factorvalues["timeunit"] = s[i+1] and factorvalues["time"] = s[i] if (y.to_s =~ /time/i && y.to_s !~ /unit/i); factorvalues["doseunit"] = s[i+1] and factorvalues["dose"] = s[i] if y.to_s =~ /dose/i; factorvalues["organism"] = s[i] if y.to_s =~ /organism/i; factorvalues["cell"] = s[i] if y.to_s =~ /cell/i; factorvalues["compound"] = s[i] if y.to_s =~ /compound/i}}; c[s[:sample_name]] = {:factorValues => [{:factorname => {:type => "literal", :value => "sample TimePoint"}, :value => {:type => "literal", :value => factorvalues["time"], :datatype => "http://www.w3.org/2001/XMLSchema#int"}, :unit => {:type => "literal", :value => factorvalues["timeunit"]}}, {:factorname => {:type => "literal", :value => "dose"}, :value => {:type => "literal", :value => factorvalues["dose"], :datatype => "http://www.w3.org/2001/XMLSchema#int"}, :unit => {:type => "literal", :value => factorvalues["doseunit"]}}, :factorname => {:type => "literal", :value => "compound"}, :value => {:type => "literal", :value => factorvalues["compound"]}], :cell => "#{factorvalues["organism"]}, #{factorvalues["cell"]}"} if s[:sample_name] =~ /\b(#{sample})\b/}}
              b.each{|k, v| v[0]["factorValues"] = c[v[0][:sample]][:factorValues]; v[0]["cell"] = c[v[0][:sample]][:cell]}
              b.each{|k, v| v.flatten!}
              head = {:head => {:vars => ["investigation", "invTitle", "featureType", "title", "value", "gene", "sample", "factorValues", "cell"]}}
              x = []
              b.each{|k,v| v.each{|a| x << a}}
              body = {"results" => {"bindings" => x}}
              File.open(File.join(dir, "#{gene}.json"), 'w') {|f| f.write(JSON.pretty_generate(head.merge(body))) } if Dir.exists?(dir)
            end
          end
        end unless genes.empty?
        puts "Delete collection #{inv}."
        my.drop
        puts "End processing derived data."
      end #datafile.blank?
    end
    puts "Finished generating json files."
  end

end

namespace :remove do

  SERVICE = "investigation" # for service config file
  require File.join '../opentox-client/lib/opentox-client.rb' # maybe adjust the paths here
  require File.join '../opentox-server/lib/opentox-server.rb'


  desc "Remove investigations without nt file."
  task :broken do
    Dir.chdir('investigation')
    IO.readlines(File.join "../broken_investigations").each do |inv|
      uri = $investigation[:uri] + '/' + inv
      # remove from backend
      OpenTox::Backend::FourStore.delete uri
      puts "#{uri} removed from backend"
      # remove from search index service
      OpenTox::RestClientWrapper.delete "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape("#{uri}")}",{},{:subjectid => OpenTox::RestClientWrapper.subjectid}
      puts "#{uri} removed from search index service."
      # remove locally
      `rm -rf #{inv}`
      `git commit -am 'removed broken #{inv}'`
      puts "#{inv} removed locally."
    end
  end

  desc "Remove investigations throwing errors while import to backend."
  task :errors do
    Dir.chdir('investigation')
    IO.readlines(File.join "../import_errors").each do |inv|
      uri = $investigation[:uri] + '/' + inv
      # remove from backend
      OpenTox::Backend::FourStore.delete uri
      puts "#{uri} removed from backend"
      # remove from search index service
      OpenTox::RestClientWrapper.delete "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape("#{uri}")}",{},{:subjectid => OpenTox::RestClientWrapper.subjectid}
      puts "#{uri} removed from search index service."
      # remove locally
      `rm -rf #{inv}`
      `git commit -am 'removed imoert error #{inv}'`
      puts "#{inv} removed locally."
    end
  end

end
