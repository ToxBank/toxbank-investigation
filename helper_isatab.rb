module OpenTox
  # full API description for ToxBank investigation service see:
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service


    module Helpers
      # check for investigation type
      def subtask_uri
        response = OpenTox::Backend::FourStore.query "SELECT ?o WHERE {<#{investigation_uri}> <#{RDF::TB}hasSubTaskURI> ?o}", "application/json"
        result = JSON.parse(response)
        type = result["results"]["bindings"].map {|n|  "#{n["o"]["value"]}"}
      end
      
      def is_isatab?
        response = OpenTox::Backend::FourStore.query "SELECT ?o WHERE {<#{investigation_uri}> <#{RDF::TB}hasInvType> ?o}", "application/json"
        result = JSON.parse(response)
        type = result["results"]["bindings"].map {|n|  "#{n["o"]["value"]}"}
        type.blank? ? (return true) : (return false)
      end
      
      # kill isa2rdf pids if delete or put
      def kill_isa2rdf
        pid = []
        pid << `ps x|grep #{params[:id]}|grep java|grep -v grep|awk '{ print $1 }'`.split("\n")
        $logger.debug "isa2rdf PIDs for current investigation:\t#{pid.flatten}\n"
        pid.flatten.each{|p| `kill #{p.to_i}`} unless pid.blank?
      end

      # copy investigation files in tmp subfolder
      def prepare_upload
        locked_error "Processing investigation #{params[:id]}. Please try again later." if File.exists? tmp
        bad_request_error "Please submit data as multipart/form-data" unless request.form_data? 
        # move existing ISA-TAB files to tmp
        FileUtils.mkdir_p tmp
        FileUtils.cp Dir[File.join(dir,"*.txt")], tmp if params[:file]
        FileUtils.cp params[:file][:tempfile], File.join(tmp, params[:file][:filename]) if params[:file]
      end

      # extract zip upload to tmp subdirectory of investigation
      def extract_zip
        unless `jar -tvf '#{File.join(tmp,params[:file][:filename])}'`.to_i == 0
          `unzip -o '#{File.join(tmp,params[:file][:filename])}'  -x '__MACOSX/*' -d #{tmp}`
          Dir["#{tmp}/*"].collect{|d| d if File.directory?(d)}.compact.each  do |d|
            `mv #{d}/* #{tmp}`
            `rmdir #{d}`
          end
        else
          FileUtils.remove_entry dir
          bad_request_error "Could not parse isatab file. Empty directory submitted."
        end
        replace_pi
      end

      def build_gene_files
        $logger.debug "Start processing derived data for #{params[:id]}."
        templates = get_templates "investigation"
        # locate derived data files and prepare
        # get information about files from assay files by sparql
        datafiles = Dir["#{dir}/*.txt"].each{|file| `dos2unix -k '#{file}'`}
        sparqlstring = File.read(templates["files_by_assays"]) % { :investigation_uri => investigation_uri }
        response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
        datafiles = JSON.parse(response)["results"]["bindings"].map{|f| f["file"]["value"]}.uniq
        @client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'ToxBank', :connect => :direct)
        my = @client[params[:id]]
        datafiles.delete_if{|file| !File.exists?(File.join(dir,file))}.reject!{|file| file =~ /^i_|^a_|^s_|ftp\:/}
        datafiles.delete_if{|file| `head -n1 '#{File.join(dir,file)}'`.encode!('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') !~ /(FC|p-value|q-value)/}
        if datafiles.blank?
          $logger.debug "No datafiles to process."
        else
          datafiles.each do |file| 
            `mongoimport -d ToxBank -c #{params[:id]} --ignoreBlanks --type tsv --file '#{File.join(dir, file)}' --headerline`
          end 
          # building genelist
          my = @client[params[:id]]
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
          assay = CSV.read(assayfiles, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
          studyfiles = Dir["#{dir}/s_*.txt"][0]
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
                assay[:data_transformation_name].each_with_index{|name, idx| a.to_a[0].each{|a| (b.has_key?(name) ? b[name] << [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => "#{a[1]}", :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "#{geneclass}:#{gene}", :sample => assay[:sample_name][idx]] : b[name] = [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => "#{a[1]}", :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "#{geneclass}:#{gene}", :sample => assay[:sample_name][idx]]) if a[0].gsub(/^FC\'|^p-value\'|^q-value\'|\'$/, "") == name } }
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
          my.drop
          $logger.debug "End processing derived data."
        end #datafile.blank?
      end

      # ISA-TAB to RDF conversion.
      # Preprocess and parse isa-tab files with java isa2rdf
      # @see https://github.com/ToxBank/isa2rdf
      def isa2rdf
        # @note isa2rdf returns correct exit code but error in task
        `cd #{File.dirname(__FILE__)}/java && java -jar -Xmx2048m isa2rdf-cli-1.0.2.jar -d #{tmp} -i #{investigation_uri} -o #{File.join tmp,nt} -t #{$user_service[:uri]} 2> #{File.join tmp,'log'} &`
        if !File.exists?(File.join tmp, nt)
          out = IO.read(File.join tmp, 'log') 
          FileUtils.remove_entry dir
          delete_investigation_policy
          bad_request_error "Could not parse isatab file in '#{params[:file][:filename]}'. Message is:\n #{out}"
        else
          `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{investigation_uri}/;g' #{File.join tmp,nt}`
          investigation_id = `grep "#{investigation_uri}/I[0-9]" #{File.join tmp,nt}|cut -f1 -d ' '`.strip
          `sed -i 's;#{investigation_id.split.last};<#{investigation_uri}>;g' #{File.join tmp,nt}`
          `echo "<#{investigation_uri}> <#{RDF.type}> <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,nt}`
          FileUtils.rm Dir[File.join(tmp,"*.zip")]
          FileUtils.cp Dir[File.join(tmp,"*")], dir
          FileUtils.remove_entry tmp

          # create dashboard cache and empty JSON object
          create_cache

          # next line moved to l.74
          `zip -j #{File.join(dir, "investigation_#{params[:id]}.zip")} #{dir}/*.txt`
          OpenTox::Backend::FourStore.put investigation_uri, File.read(File.join(dir,nt)), "application/x-turtle"

          if request.request_method =~ /PUT/
            # delete existing json files and cancel subtask if still running
            subtaskuri = subtask_uri[0]
            unless subtaskuri.blank?
              $logger.debug "cancel running subtask: #{subtaskuri}"
              `curl -Lk -X PUT -d '' '#{subtaskuri}/Cancelled'`
            end
            jsonfiles = Dir["#{dir}/*.json"]
            jsonfiles.each{|file| FileUtils.rm(file)} unless jsonfiles.blank?
          end

          task = OpenTox::Task.run("Processing derived data",investigation_uri) do
            $logger.debug "build_gene_files"
            build_gene_files
            # update JSON object with dashboard values
            dashboard_cache
            link_ftpfiles
            # remove subtask uri from metadata
            OpenTox::Backend::FourStore.update "WITH <#{investigation_uri}>
            DELETE { <#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> ?o}
            WHERE {<#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> ?o}"
            set_modified
            investigation_uri # result uri for subtask
          end # task
          # update metadata with subtask uri
          triplestring = "<#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> <#{task.uri}> ."
          OpenTox::Backend::FourStore.post investigation_uri, triplestring, "application/x-turtle"
          investigation_uri
        end
      end
      
      # create dashboard cache
      def dashboard_cache
        $logger.debug "build dashboard"
        templates = get_templates "investigation"
        sparqlstring = File.read(templates["factorvalues_by_investigation"]) % { :investigation_uri => investigation_uri }
        factorvalues = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
        @result = JSON.parse(factorvalues)
        bindings = @result["results"]["bindings"]
        unless bindings.blank?
          # init arrays; a = by sample_uri; b = compare samples; c = uniq result
          a = []; b = []; c = []
          bindings.each{|b| a << bindings.map{|x| x if x["sample"]["value"] == b["sample"]["value"]}.compact }
          # compare and uniq sample [compound, dose, time]
          a.each do |sample|
            @collected_values = []
            sample.each do |s|
              compound = s["value"]["value"] if s["factorname"]["value"] =~ /compound/i
              dose = s["value"]["value"] if s["factorname"]["value"] =~ /dose/i
              time = s["value"]["value"] if s["factorname"]["value"] =~ /time/i
              @collected_values << [compound, dose, time]
            end
            collected_values = @collected_values.flatten.compact
            if !b.include?(collected_values)
              b << collected_values
              c << sample
            end
          end
          # clear original bindings
          @result["results"]["bindings"].clear
          # add new bindings
          @result["results"]["bindings"] = c.flatten!
          
          # add biosample characteristics
          biosamples = @result["results"]["bindings"].map{|n| n["biosample"]["value"]}
          # add new JSON head
          @result["head"]["vars"] << "characteristics"
          biosamples.uniq.each do |biosample|
            sparqlstring = File.read(templates["characteristics_by_sample"]) % { :sample_uri => biosample }
            sample = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
            result = JSON.parse(sample)
            # adding single biosample characteristics to JSON array
            @result["results"]["bindings"].find{|n| n["characteristics"] = result["results"]["bindings"] if n["biosample"]["value"].to_s == biosample.to_s }
          end
          # add sample characteristics
          samples = @result["results"]["bindings"].map{|n| n["sample"]["value"]}
          # add new JSON head
          @result["head"]["vars"] << "sampleChar"
          samples.uniq.each do |sample|
            sparqlstring = File.read(templates["characteristics_by_sample"]) % { :sample_uri => sample }
            response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
            result = JSON.parse(response)
            # adding single sample characteristics to JSON array
            @result["results"]["bindings"].find{|n| n["sampleChar"] = result["results"]["bindings"] if n["sample"]["value"].to_s == sample.to_s}
          end
          @result["results"]["bindings"].each{|n| n["characteristics"] ||= [] }
          @result["results"]["bindings"].each{|n| n["sampleChar"] ||= [] }
          # result to JSON
          result = JSON.pretty_generate(@result)
          # write result to dashboard_file
          replace_cache result
        else
          $logger.error "Unable to create dashboard file for investigation #{params[:id]}"
        end
      end

      # @!group Helpers to link FTP data 
      # link data files from FTP to investigation dir
      def link_ftpfiles
        $logger.debug "build FTP links"
        ftpfiles = get_ftpfiles
        datafiles = get_datafiles
        return "" if ftpfiles.empty? || datafiles.empty?
        remove_symlinks
        datafiles = datafiles.collect { |f| f.gsub(/(ftp:\/\/|)#{URI($investigation[:uri]).host}\//,"") }
        tolink = (ftpfiles.keys & ( datafiles - Dir.entries(dir).reject{|entry| entry =~ /^\.{1,2}$/}))
        tolink.each do |file|
          `ln -s "/home/ftpusers/#{Authorization.get_user}/#{file}" "#{dir}/#{file.gsub("/","_")}"`
          @datahash[file].each do |data_node|
            OpenTox::Backend::FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{data_node}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file.gsub("/","_")}>}}"
            ftpfilesave = "<#{data_node}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file.gsub("/","_")}> ."
            File.open(File.join(dir, "ftpfiles.nt"), 'a') {|f| f.write("#{ftpfilesave}\n") }
          end
        end
        return tolink
      end
      # @!endgroup

    end
  end
end
