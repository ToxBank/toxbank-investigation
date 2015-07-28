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
        response = OpenTox::Backend::FourStore.query sparqlstring, "application/json"
        #$logger.debug response
        datafiles = JSON.parse(response)["results"]["bindings"].map{|f| f["file"]["value"]}.uniq
        $logger.debug "datafiles: #{datafiles}"
        #datafiles.reject{|f| f =~ /ftp\:/}
        @client = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'ToxBank', :connect => :direct)
        my = @client[params[:id]]
        datafiles.reject!{|file| file =~ /^i_|^a_|^s_|ftp\:/}.each do |file| 
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
        investigationfile = Dir["#{dir}/i_*.txt"][0]
        inv = CSV.read(investigationfile, { :col_sep => "\t", :row_sep => :auto, :headers => true, :header_converters => :symbol })
        inv.find{|r| @title = r[1] if r[0] == "Investigation Title"}
        genes = genelist
        # working with genes
        #TODO write right gene class key e.g. Symbol: TSPAN6
        genes.each do |gene|
          out = []
          unless File.exists?(File.join(dir, "#{gene}.json"))
            a = (gene.class == String ? my.find(Symbol: "#{gene}").each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}} : my.find(Entrez: gene).each{|hash| hash.delete_if{|k, v| k !~ /^p-value|^q-value|^FC/}} )
            unless a.blank?
              b = {}
              assay[:data_transformation_name].each_with_index{|name, idx| a.to_a[0].each{|a| (b.has_key?(name) ? b[name] << [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => a[1], :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "Symbol:#{gene}", :sample => assay[:sample_name][idx]] : b[name] = [:investigation => {:type => "uri", :value => investigation_uri}, :invTitle => {:type => "literal", :value => @title}, :featureType => {:type => "uri", :value=> (("http://onto.toxbank.net/isa/pvalue" if a[0] =~ /p-value/) or ("http://onto.toxbank.net/isa/qvalue" if a[0] =~ /q-value/) or ("http://onto.toxbank.net/isa/FC" if a[0] =~ /FC/)) }, :title => {:type => "literal", :value => a[0]}, :dataTransformationName => {:type => "literal", :value => name}, :value => {:type => "literal", :value => a[1], :datatype => "http://www.w3.org/2001/XMLSchema#double"}, :gene => "Symbol:#{gene}", :sample => assay[:sample_name][idx]]) if a[0] =~ /\b(#{name})\b/ } }
              c = {}
              assay[:sample_name].each{|sample| study.each{|x| c[x[-1]] = {:factorValues => [{:factorname => {:type => "literal", :value => "sample TimePoint"}, :value => {:type => "literal", :value => x[28], :datatype => "http://www.w3.org/2001/XMLSchema#int"}, :unit => {:type => "literal", :value => x[29]}}, {:factorname => {:type => "literal", :value => "dose"}, :value => {:type => "literal", :value => x[23], :datatype => "http://www.w3.org/2001/XMLSchema#int"}, :unit => {:type => "literal", :value => x[24]}}, :factorname => {:type => "literal", :value => "compound"}, :value => {:type => "literal", :value => x[18]}], :cell => "#{x[2]},#{x[13]}"} if x[-1] =~ /\b(#{sample})\b/}}
              b.each{|k, v| v[0]["factorValues"] = c[v[0][:sample]][:factorValues]; v[0]["cell"] = c[v[0][:sample]][:cell]}
              b.each{|k, v| v.flatten!}
              head = {:head => {:vars => ["investigation", "invTitle", "featureType", "title", "value", "gene", "sample", "factorValues", "cell"]}}
              x = []
              b.each{|k,v| v.each{|a| x << a}}
              body = {"results" => {"bindings" => x}}
              File.open(File.join(dir, "#{gene}.json"), 'w') {|f| f.write(JSON.pretty_generate(head.merge(body))) }
            end
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
          
          task = OpenTox::Task.run("Processing derived data",investigation_uri) do
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
