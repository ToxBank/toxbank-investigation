require "opentox-server"
require "#{File.dirname(__FILE__)}/tb_policy.rb"

module OpenTox
  class Application < Service

    helpers do

      def uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      def uri_list 
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f| to(f.sub(/\.\//,'')) }# new
        uris.collect!{|u| u.sub(/(\/#{params[:id]}\/)/,'\1isatab/')} if params[:id]
        uris.compact.sort.join("\n") + "\n"
      end

      def dir
        File.join File.dirname(File.expand_path __FILE__), "investigation", params[:id].to_s
      end

      def tmp
        File.join dir,"tmp"
      end

      def file
        File.join dir, params[:filename]
      end

      def n3
        "#{params[:id]}.n3"
      end

      def prepare_upload
        # remove stale directories from failed tests
        stale_files = `cd #{File.dirname(__FILE__)}/investigation && git ls-files --others --exclude-standard --directory`.chomp
        `cd #{File.dirname(__FILE__)}/investigation && rm -rf #{stale_files}` unless stale_files.empty?
        # lock tmp dir
        locked_error "Processing investigation #{params[:id]}. Please try again later." if File.exists? tmp
        bad_request_error "Please submit data as multipart/form-data" unless request.form_data?
        # move existing ISA-TAB files to tmp
        FileUtils.mkdir_p tmp
        FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
        File.open(File.join(tmp, params[:file][:filename]), "w+"){|f| f.puts params[:file][:tempfile].read}
      end

      def extract_zip
        # overwrite existing files with new submission
        `unzip -o #{File.join(tmp,params[:file][:filename])} -d #{tmp}`
        Dir["#{tmp}/*"].collect{|d| d if File.directory?(d)}.compact.each  do |d|
          `mv #{d}/* #{tmp}`
          `rmdir #{d}`
        end
      end

      def extract_xls
        # use Excelx.new instead of Excel.new if your file is a .xlsx
        xls = Excel.new(File.join(tmp, params[:file][:filename])) if params[:file][:filename].match(/.xls$/)
        xls = Excelx.new(File.join(tmp, params[:file][:filename])) if params[:file][:filename].match(/.xlsx$/)
        xls.sheets.each_with_index do |sh, idx|
          name = sh.to_s
          xls.default_sheet = xls.sheets[idx]
          1.upto(xls.last_row) do |ro|
            1.upto(xls.last_column) do |co|
              unless (co == xls.last_column)
                File.open(File.join(tmp, name + ".txt"), "a+"){|f| f.print "#{xls.cell(ro, co)}\t"}
              else
                File.open(File.join(tmp, name + ".txt"), "a+"){|f| f.print "#{xls.cell(ro, co)}\n"}
              end
            end
          end
        end   
      rescue
        bad_request_error "Could not parse spreadsheet #{params[:file][:filename]}"
      end

      def isa2rdf
        begin # isa2rdf returns correct exit code
          `cd #{File.dirname(__FILE__)}/java && java -jar isa2rdf-0.0.3-SNAPSHOT.jar -d #{tmp} -o #{File.join tmp,n3} &> #{File.join tmp,'log'}`
        rescue
          log = File.read File.join(tmp,"log")
          FileUtils.remove_entry dir
          bad_request_error "ISA-TAB validation failed:\n#{log}", uri
        end
        # rewrite default prefix
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{uri}/;' #{File.join tmp,n3}`
        # add owl:sameAs to identify investigation later
        investigation_id = `grep ":I[0-9]" #{File.join tmp,n3}|cut -f1 -d ' '`.strip
        `sed -i 's;#{investigation_id};:;' #{File.join tmp,n3}`
        `echo "\n: a <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,n3}`
        #`echo "\n: owl:sameAs #{investigation_id} ." >>  #{File.join tmp,n3}`
        FileUtils.rm Dir[File.join(tmp,"*.zip")]
        # if everything is fine move ISA-TAB files back to original dir
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        # git commit
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files --others --exclude-standard --directory`
        `cd #{File.dirname(__FILE__)}/investigation && git add #{newfiles}`
        ['application/zip', 'application/vnd.ms-excel'].include?(params[:file][:type]) ? action = "created" : action = "modified"
        `cd #{File.dirname(__FILE__)}/investigation && git commit -am "investigation #{params[:id]} #{action} by #{request.ip}"`
        # create new zipfile
        zipfile = File.join dir, "investigation_#{params[:id]}.zip"
        `zip -j #{zipfile} #{dir}/*.txt`
        # store RDF
        four_store_uri = $four_store[:uri].sub(%r{//},"//#{$four_store[:user]}:#{$four_store[:password]}@")
        RestClient.put File.join(four_store_uri,"data",uri), File.read(File.join(dir,n3)), :content_type => "application/x-turtle" # content-type not very consistent in 4store
        FileUtils.remove_entry tmp  # unlocks tmp
        OpenTox::Authorization.check_policy(uri, @subjectid)
        puts "params[:allowReadByUser]    #{params[:allowReadByUser].to_s} "
        $logger.debug "mr ::: xyz appl: params[:allowReadByUser]: #{params[:allowReadByUser]}"
        create_policies params[:allowReadByUser] if params[:allowReadByUser]
        create_policies params[:allowReadByGroup] if params[:allowReadByGroup]
        uri
      end

      def create_policies uristring
        uriarray = uristring.split(",")
        $logger.debug "mr ::: xyz #{uriarray.inspect}"
        uriarray.each do |u|
          $logger.debug "mr ::: xyz cp u: #{u}"
          tbaccount = OpenTox::TBAccount.new(u, @subjectid)
          tbaccount.send_policy(uri)
        end
      end
    end

    before do
      not_found_error "Directory #{dir} does not exist."  unless File.exist? dir
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
    end

    # Query all investigations or get a list of all investigations
    # Requests with a query parameter will perform a SPARQL query on all investigations
    # @return [application/sparql-results+json] Query result
    # @return [text/uri-list] List of investigations
    get '/investigation/?' do
      if params[:query] # pass SPARQL query to 4store
        FourStore.query params[:query], request.env['HTTP_ACCEPT']
      else
        FourStore.list request.env['HTTP_ACCEPT']
      end
    end

    # Create a new investigation from ISA-TAB files
    # @param [Header] Content-type: multipart/form-data
    # @param file Zipped investigation files in ISA-TAB format
    # @return [text/uri-list] Investigation URI 
    post '/investigation/?' do
      params[:id] = SecureRandom.uuid
      #params[:id] = next_id
      mime_types = ['application/zip','text/tab-separated-values', "application/vnd.ms-excel"]
      bad_request_error "No file uploaded." unless params[:file]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file][:filename]}: Uploding, validating and converting to RDF") do
        prepare_upload
        case params[:file][:type]
        when "application/vnd.ms-excel"
          extract_xls
        when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          extract_xls
        when 'application/zip'
          extract_zip
        #when  'text/tab-separated-values' # do nothing, file is already in tmp
        end
        isa2rdf
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Get an investigation representation
    # @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
    # @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
    get '/investigation/:id' do
      not_found_error "Investigation #{uri} does not exist."  unless File.exist? dir # not called in before filter???
      case @accept
      when "text/tab-separated-values"
        send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
      when "text/uri-list"
        uri_list
      when "application/zip"
        send_file File.join dir, "investigation_#{params[:id]}.zip"
      else
        FourStore.query "CONSTRUCT { ?s ?p ?o } FROM <#{uri}> WHERE {?s ?p ?o } LIMIT 15000", @accept
      end
    end

    # Get investigation metadata in RDF
    get '/investigation/:id/metadata' do
      not_found_error "Investigation #{uri} does not exist."  unless File.exist? dir # not called in before filter???
      FourStore.query "CONSTRUCT { ?s ?p ?o.  } FROM <#{uri}> WHERE { ?s <#{RDF.type}> <http://onto.toxbank.net/isa/Investigation>. ?s ?p ?o .  } ", @accept
    end

    # Get a study, assay, data representation
    # @param [Header] one of text/tab-separated-values, application/sparql-results+json
    # @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
    get '/investigation/:id/isatab/:filename'  do
      not_found_error "File #{File.join uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
      # TODO: returns text/plain content type for tab separated files
      send_file file, :type => File.new(file).mime_type
    end

    # Get RDF for an investigation resource
    get '/investigation/:id/:resource' do
      FourStore.query " CONSTRUCT {  <#{File.join(uri,params[:resource])}> ?p ?o.  } FROM <#{uri}> WHERE { <#{File.join(uri,params[:resource])}> ?p ?o .  } ", @accept
    end

    # Add studies, assays or data to an investigation
    # @param [Header] Content-type: multipart/form-data
    # @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
    post '/investigation/:id' do
      mime_types = ['application/zip','text/tab-separated-values', "application/vnd.ms-excel"]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file][:filename]}: Uploding, validationg and converting to RDF") do
        prepare_upload
        isa2rdf
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Delete an investigation
    delete '/investigation/:id' do
      FileUtils.remove_entry dir
      # git commit
      `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{request.ip}"`
      # updata RDF
      FourStore.delete uri
      if @subjectid and !File.exists?(dir) and uri
        begin
          res = OpenTox::Authorization.delete_policies_from_uri(uri, @subjectid)
          LOGGER.debug "Policy deleted for Investigation URI: #{uri} with result: #{res}"
        rescue
          $logger.warn "Policy delete error for Investigation URI: #{uri}"
        end
      end
      response['Content-Type'] = 'text/plain'
      "Investigation #{params[:id]} deleted"
    end

    # Delete an individual study, assay or data file
    delete '/investigation/:id/:filename'  do
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "Deleting #{params[:file][:filename]} from investigation #{params[:id]}.") do
        prepare_upload
        File.delete File.join(tmp,params[:filename])
        isa2rdf
        "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

  end
end
