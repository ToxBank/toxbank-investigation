module OpenTox
  # full API description for ToxBank investigation service see:
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    module Helpers
      # check for investigation type
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
        $logger.debug "Start processing derived data."
        templates = get_templates "investigation"
        # locate derived data files and prepare
        # get information about files from assay files by sparql
        datafiles = Dir["#{dir}/*.txt"].each{|file| `dos2unix -k '#{file}'`}
        sparqlstring = File.read(templates["files_by_assays"]) % { :investigation_uri => investigation_uri }
        $logger.debug sparqlstring
        response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
        $logger.debug response
        datafiles = JSON.parse(response)["results"]["bindings"].map{|f| f["file"]["value"]}.uniq
        $logger.debug "datafiles: #{datafiles}"
        #datafiles.reject{|f| f =~ /ftp\:/}
        @client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'ToxBank', :connect => :direct)
        my = @client[params[:id]]
        datafiles.reject!{|file| file =~ /^i_|^a_|^s_|ftp\:/}.each do |file| 
          #`sed '1;.;\u002e;g' #{File.join(dir, file)}`
          #`dos2unix -k '#{File.join(dir, file)}'`
          #`sed '1 s;\.;U+FF0E;g' #{File.join(dir, file)}`
          # setup database and import derived data files.
          $logger.debug "import file: #{file}"
          `mongoimport -d ToxBank -c #{params[:id]} --ignoreBlanks --upsert --type tsv --file '#{File.join(dir, file)}' --headerline`
        end unless datafiles.blank?
        # building genelist
        my = @client[params[:id]]
        symbol = my.find.distinct(:Symbol)
        entrez = my.find.distinct(:Entrez)
        genelist = symbol+entrez
        $logger.debug genelist
        # write to file
        File.open(File.join(dir, "genelist"), 'w') {|f| f.write(genelist.reject!{|g| g.to_s =~ /^NA$|^0$/}) }
        #$logger.debug genelist
        # TODO could be more than one assay or study
        assayfiles = Dir["#{dir}/a_*.txt"][0]
        #file = datafiles.find{|f| f =~ /\/a_/ }
        $logger.debug assayfiles
        assay = CSV.read(assayfiles, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
        $logger.debug assay.headers
        #file = datafiles.find{|f| f =~ /\/s_/ }
        studyfiles = Dir["#{dir}/s_*.txt"][0]
        $logger.debug studyfiles
        study = CSV.read(studyfiles, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
        genes = genelist
        # working with genes
        genes.each do |gene|
          out = []
          #$logger.debug "biosearch for: #{gene}"
          #$logger.debug "File exists ? :#{File.exists?(File.join(dir, "#{gene}.json"))}\n"
          unless File.exists?(File.join(dir, "#{gene}.json"))
            a = (gene.class == String ? my.find(Symbol: "#{gene}").each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}} : my.find(Entrez: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}} )
            #$logger.debug a.to_a
            unless a.blank?
              #$logger.debug "database: #{a.to_a}"
              #$logger.debug "assay: #{assay.headers}"
              b = {}
              assay[:data_transformation_name].each_with_index{|name, idx| a.to_a[0].each{|a| b[name] = [:title => a[0], :value => a[1], :sampleNr => assay[:sample_name][idx]] if a[0] =~ /\b(#{name})\b/ } }
              c = {}
              #$logger.debug "assay sample names: #{assay[:sample_name]}"
              assay[:sample_name].each{|sample| study.each{|x| c[x[-1]] = ["#{x[2]}", "#{x[13]}", "#{x[18]}", "#{x[23]}", "#{x[24]}", "#{x[28]}", "#{x[29]}"] if x[-1] =~ /\b(#{sample})\b/}}
              #b.each{|k, v|  v << c[v.last] }
              $logger.debug c
              b.each{|k, v| v << [:factorValues => c[v[0][:sampleNr]]] }
              b.each{|k, v|  v.flatten!}
              File.open(File.join(dir, "#{gene}.json"), 'w') {|f| f.write(JSON.pretty_generate(b)) }
            end
            #sparqlstring = File.read(templates["factors_with_samplnr"]) % { :investigation_uri => investigation_uri }
            #$logger.debug sparqlstring
            #response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
            #$logger.debug response
            #@a = JSON.parse(response)
            #@a["head"]["vars"] << "gene"
            #@a["head"]["vars"] << "sample"
            #@a["head"]["vars"] << "factorValues"
            #@a["head"]["vars"] << "cell"
            # set headers for output
            #out << {"head" => {"vars" => @a["head"]["vars"]}}
            # search in files for sample by transformation name
            #$logger.debug gene
            #@a["results"]["bindings"].each{|n| n["gene"] = "#{gene.split("/").last(2).join(":")}"}
            #transNames = @a["results"]["bindings"].map{|n| [n["investigation"]["value"], n["dataTransformationName"]["value"]] }
            #samples = []
            #cells = []
            #transNames.each do |n|
            #  sample = `grep "#{n[1]}" #{File.join dir, "a_*" }|cut -f1`.chomp.gsub("\"", "").split("\n").delete_if{|s| s =~ /control/i}.first
            #  #$logger.debug sample
            #  cell = `grep "#{sample}" #{File.join dir, "s_*" }|cut --fields=3,14`.chomp.gsub("\"", "").gsub("\t", ",")
            #  #$logger.debug cell
            #  samples << {n[1] => sample}
            #  cells << cell
            #end
            #match_index = []
            #samples.uniq.each do |nr|
            #  nr.each do |k, v|
            #    match_index = @a["results"]["bindings"].index(@a["results"]["bindings"].find{ |n| n["dataTransformationName"]["value"] == k })
            #    @a["results"]["bindings"][match_index]["sample"] = v
            #    sparqlstring = File.read(templates["biosearch_sample"]) % { :investigation_uri => investigation_uri, :sampl => v}
            #    response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
            #    @a["results"]["bindings"][match_index]["factorValues"] = JSON.parse(response)["results"]["bindings"]
            #    @a["results"]["bindings"][match_index]["cell"] = cells[match_index]
            #  end
            #end
            #out << {"results" => {"bindings" => @a["results"]["bindings"].flatten}}
            #out = out.uniq.compact.flatten
            # assemble json hash
            #head = out[0]
            #body = out[1]
            # generate json object
            #js = JSON.pretty_generate(head.merge(body))
            #File.open(File.join(dir, "#{gene.split("/").last}.json"), 'w') {|f| f.write(js) }
            #sleep 1
          end
        end unless genes.empty?
        $logger.debug "End processing derived data."
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
          
          task = OpenTox::Task.run("Processing raw data",investigation_uri) do
            sleep 30 # wait until metadata imported and preview requested
=begin
            `cd #{File.dirname(__FILE__)}/java && java -jar -Xmx2048m isa2rdf-cli-1.0.2.jar -d #{dir} -i #{investigation_uri} -a #{File.join dir} -o #{File.join dir,nt} -t #{$user_service[:uri]} 2> #{File.join dir,'log'} &`
            # get rdfs
            sleep 10 # wait until first file is generated
            rdfs = Dir["#{dir}/*.rdf"]
            $logger.debug "rdfs:\t#{rdfs}\n"
            unless rdfs.blank?
              sleep 1
              rdfs = Dir["#{dir}/*.rdf"].reject!{|rdf| rdf.blank?}
            else
              investigation_id = `grep "#{investigation_uri}/I[0-9]" #{File.join dir,nt}|cut -f1 -d ' '`.strip
              `sed -i 's;#{investigation_id.split.last};<#{investigation_uri}>;g' #{File.join dir,nt}`
              # get ntriples datafiles
              datafiles = Dir["#{dir}/*.nt"].reject!{|file| file =~ /#{nt}$|ftpfiles\.nt$|modified\.nt$|isPublished\.nt$|isSummarySearchable\.nt/}
              $logger.debug "datafiles:\t#{datafiles}"
              unless datafiles.blank?
                # split extra datasets
                #datafiles.each{|dataset| `split -a 4 -d -l 100000 '#{dataset}' '#{dataset}_'` unless File.zero?(dataset)}
                #chunkfiles = Dir["#{dir}/*.nt_*"]
                #$logger.debug "chunkfiles:\t#{chunkfiles}"
                
                # append datasets to investigation graph
                #chunkfiles.sort{|a,b| a <=> b}.each do |dataset|
                datafiles.each do |dataset|
                  OpenTox::Backend::FourStore.post investigation_uri, File.read(dataset), "application/x-turtle"
                  sleep 10 # time it takes to import and reindex
                  set_modified
                  #File.delete(dataset)
                end
              end # datafiles
            end # rdfs
=end
            build_gene_files
=begin        
            # update JSON object with dashboard values
            dashboard_cache
            link_ftpfiles
            # remove subtask uri from metadata
            OpenTox::Backend::FourStore.update "WITH <#{investigation_uri}>
            DELETE { <#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> ?o}
            WHERE {<#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> ?o}"
            set_modified
=end
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
