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
        `unzip -o '#{File.join(tmp,params[:file][:filename])}' -d #{tmp}`
        Dir["#{tmp}/*"].collect{|d| d if File.directory?(d)}.compact.each  do |d|
          `mv #{d}/* #{tmp}`
          `rmdir #{d}`
        end
        # zip original files for download
        `zip -x #{tmp}/*.zip -j #{File.join(tmp, "investigation_#{params[:id]}.zip")} #{tmp}/*`
        replace_pi
      end
      
      # ISA-TAB to RDF conversion.
      # Preprocess and parse isa-tab files with java isa2rdf
      # @see https://github.com/ToxBank/isa2rdf
      def isa2rdf
        # @note isa2rdf returns correct exit code but error in task
        # @todo delete dir if task catches error, pass error to block
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
          # `echo '\n<#{investigation_uri}> <#{RDF::DC.modified}> "#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}" .' >> #{File.join tmp,nt}`
          `echo "<#{investigation_uri}> <#{RDF.type}> <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,nt}`
          #FileUtils.rm Dir[File.join(tmp,"*.zip")]
          FileUtils.cp Dir[File.join(tmp,"*")], dir
          # next line moved to l.74
          #`zip -j #{File.join(dir, "investigation_#{params[:id]}.zip")} #{dir}/*.txt`
          OpenTox::Backend::FourStore.put investigation_uri, File.read(File.join(dir,nt)), "application/x-turtle"
          
          task = OpenTox::Task.run("Processing raw data",investigation_uri) do
            `cd #{File.dirname(__FILE__)}/java && java -jar -Xmx2048m isa2rdf-cli-1.0.2.jar -d #{tmp} -i #{investigation_uri} -a #{File.join tmp} -o #{File.join tmp,nt} -t #{$user_service[:uri]} 2> #{File.join tmp,'log'} &`
            # get rdfs
            sleep 1 # wait until first file is generated
            rdfs = Dir["#{tmp}/*.rdf"]
            $logger.debug "rdfs:\t#{rdfs}\n"
            unless rdfs.blank?
              sleep 1
              rdfs = Dir["#{tmp}/*.rdf"].reject!{|rdf| rdf.blank?}
            else
              # get ntriples datafiles
              datafiles = Dir["#{tmp}/*.nt"].reject!{|file| file =~ /#{nt}$|ftpfiles\.nt$|modified\.nt$|isPublished\.nt$|isSummarySearchable\.nt/}
              $logger.debug "datafiles:\t#{datafiles}"
              unless datafiles.blank?
                # split extra datasets
                datafiles.each{|dataset| `split -d -l 200000 '#{dataset}' '#{dataset}_'` unless File.zero?(dataset)}
                chunkfiles = Dir["#{tmp}/*.nt_*"]
                $logger.debug "chunkfiles:\t#{chunkfiles}"
                
                # append datasets to investigation graph
                chunkfiles.each do |dataset|
                  OpenTox::Backend::FourStore.post investigation_uri, File.read(dataset), "application/x-turtle"
                  sleep 1
                  set_modified
                  File.delete(dataset)
                end
                datafiles.each{|file| FileUtils.cp file, dir}
              end # datafiles
            end # rdfs
            FileUtils.remove_entry tmp
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
          link_ftpfiles
          investigation_uri
        end
      end
      
      # link files uploaded to FTP
      def link_ftpfiles
        ftpfiles = get_ftpfiles
        datafiles = get_datafiles
        return "" if ftpfiles.empty? || datafiles.empty?
        remove_symlinks
        datafiles = Hash[datafiles.collect { |f| [File.basename(f), f.gsub(/(ftp:\/\/|)#{URI($investigation[:uri]).host}\//,"")] }]
        tolink = (ftpfiles.keys & ( datafiles.keys - Dir.entries(dir).reject{|entry| entry =~ /^\.{1,2}$/}))
        tolink.each do |file|
          `ln -s "#{ftpfiles[file]}" "#{dir}/#{file}"`
          @datahash[file].each do |data_node|
            OpenTox::Backend::FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{data_node}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file}>}}"
            ftpfilesave = "<#{data_node}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file}> ."
            File.open(File.join(dir, "ftpfiles.nt"), 'a') {|f| f.write("#{ftpfilesave}\n") }
          end
        end
        return tolink
      end

    end
  end
end
