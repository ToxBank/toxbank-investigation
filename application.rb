require 'opentox-server'
require "#{File.dirname(__FILE__)}/tbaccount.rb"
require "#{File.dirname(__FILE__)}/pirewriter.rb"

module OpenTox
  class Application < Service

    helpers do

      def investigation_uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      def uri_list 
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f| to(f.sub(/\.\//,'')) }
        uris.collect!{|u| u.sub(/(\/#{params[:id]}\/)/,'\1isatab/')} if params[:id]
        uris.delete_if{|u| u.match(/_policies$/)}
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
        #stale_files = `cd #{File.dirname(__FILE__)}/investigation && git ls-files --others --exclude-standard --directory`.chomp
        #`cd #{File.dirname(__FILE__)}/investigation && rm -rf #{stale_files}` unless stale_files.empty?
        # lock tmp dir
        locked_error "Processing investigation #{params[:id]}. Please try again later." if File.exists? tmp
        bad_request_error "Please submit data as multipart/form-data" unless request.form_data?
        # move existing ISA-TAB files to tmp
        FileUtils.mkdir_p tmp
        FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
        FileUtils.cp params[:file][:tempfile], File.join(tmp, params[:file][:filename])
      end

      def extract_zip
        # overwrite existing files with new submission
        `unzip -o #{File.join(tmp,params[:file][:filename])} -d #{tmp}`
        Dir["#{tmp}/*"].collect{|d| d if File.directory?(d)}.compact.each  do |d|
          `mv #{d}/* #{tmp}`
          `rmdir #{d}`
        end
        replace_pi @subjectid
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
          bad_request_error "ISA-TAB validation failed:\n#{log}", investigation_uri
        end
        # rewrite default prefix
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{investigation_uri}/;' #{File.join tmp,n3}`
        # add owl:sameAs to identify investigation later
        investigation_id = `grep ":I[0-9]" #{File.join tmp,n3}|cut -f1 -d ' '`.strip
        `sed -i 's;#{investigation_id};:;' #{File.join tmp,n3}`
        `echo "\n: a <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,n3}`
        #`echo "\n: owl:sameAs #{investigation_id} ." >>  #{File.join tmp,n3}`
        FileUtils.rm Dir[File.join(tmp,"*.zip")]
        # if everything is fine move ISA-TAB files back to original dir
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        # create new zipfile
        zipfile = File.join dir, "investigation_#{params[:id]}.zip"
        `zip -j #{zipfile} #{dir}/*.txt`
        # store RDF
        c_length = File.size(File.join dir,n3)
        RestClient.put File.join(FourStore.four_store_uri,"data",investigation_uri), File.read(File.join(dir,n3)), {:content_type => "application/x-turtle", :content_length => c_length} # content-type not very consistent in 4store
        FileUtils.remove_entry tmp  # unlocks tmp
        # git commit
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files --others --exclude-standard --directory #{params[:id]}`
        `cd #{File.dirname(__FILE__)}/investigation && git add #{newfiles}`
        ['application/zip', 'application/vnd.ms-excel'].include?(params[:file][:type]) ? action = "created" : action = "modified"
        `cd #{File.dirname(__FILE__)}/investigation && git commit -am "investigation #{params[:id]} #{action} by #{request.ip}"`
        investigation_uri
      end

      def create_policy ldaptype, uristring
        begin
          filename = File.join(dir, "#{ldaptype}_policies")
          policyfile = File.open(filename,"w")
          uriarray = uristring.split(",")
          uriarray.each do |u|
            tbaccount = OpenTox::TBAccount.new(u, @subjectid)
            policyfile.puts tbaccount.get_policy(investigation_uri)
          end
          policyfile.close
          policytext = File.read filename
          replace = policytext.gsub!("</Policies>\n<!DOCTYPE Policies PUBLIC \"-//Sun Java System Access Manager7.1 2006Q3 Admin CLI DTD//EN\" \"jar://com/sun/identity/policy/policyAdmin.dtd\">\n<Policies>\n", "")
          File.open(filename, "w") { |file| file.puts replace } if replace
          Authorization.reset_policies investigation_uri, ldaptype, @subjectid
          ret = Authorization.create_policy(File.read(policyfile), @subjectid)
          File.delete policyfile if ret
        rescue
          $logger.warn "create policies error for Investigation URI: #{investigation_uri} for user/group uris: #{uristring}"
        end
      end

      def set_flag flag, value, type = ""
        flagtype = type == "boolean" ? "^^<#{RDF::XSD.boolean}>" : ""
        FourStore.update "DELETE DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}/> <#{flag}> \"#{!value}\"#{flagtype}}}"
        FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}/> <#{flag}> \"#{value}\"#{flagtype}}}"
      end

      def is_pi?(subjectid)
        $logger.debug "uri owner: #{OpenTox::Authorization.get_uri_owner(investigation_uri, subjectid)}"
        $logger.debug "user name: #{OpenTox::Authorization.get_user(subjectid)}"
        OpenTox::Authorization.get_uri_owner(investigation_uri, subjectid) == OpenTox::Authorization.get_user(subjectid) ? true : false
      end

      def qfilter(flag, uri=nil)
        if uri == nil
          qfilter = FourStore.query "SELECT ?s FROM <#{investigation_uri}> WHERE {?s <#{RDF::TB}#{flag}> ?o FILTER regex(?o, 'true', 'i')}", "application/sparql-results+xml"
          qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '')
        else
          qfilter = FourStore.query "SELECT ?s FROM <#{uri}> WHERE {?s <#{RDF::TB}#{flag}> ?o FILTER regex(?o, 'true', 'i')}", "application/sparql-results+xml"
          qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '')
        end
      end

      def protected!(subjectid)
        if env["session"]
          unless authorized?(subjectid) || OpenTox::Authorization.is_token_valid(subjectid)
            flash[:notice] = "You don't have access to this section: "
            redirect back
        end
        elsif !env["session"] && subjectid
          unless authorized?(subjectid) || OpenTox::Authorization.is_token_valid(subjectid)
            $logger.debug "URI not authorized: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").sub("http://","https://").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
            raise OpenTox::NotAuthorizedError.new "Not authorized"
          end
        else
          raise OpenTox::NotAuthorizedError.new "Not authorized" unless authorized?(subjectid) || OpenTox::Authorization.is_token_valid(subjectid)
        end
      end

      def qlist
        list = FourStore.list(to("/investigation"), "text/uri-list")
        list.split.keep_if{|v| v =~ %r{#{$investigation[:uri]}} && (OpenTox::Authorization.get_uri_owner(v, @subjectid) == OpenTox::Authorization.get_user(@subjectid) || qfilter("isSummarySearchable") || qfilter("isPublished", v))}.join("\n")
      end

    end

    before do
      resource_not_found_error "Directory #{dir} does not exist."  unless File.exist? dir
      parse_input if request.request_method =~ /POST|PUT/
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
    end

    # Query all investigations or get a list of all investigations
    # Requests with a query parameter will perform a SPARQL query on all investigations
    # @return [application/sparql-results+json] Query result
    # @return [text/uri-list] List of investigations
    # include own, published and metadata from searchable
    get '/investigation/?' do
      if params[:query] 
        # sparql over own and published investigations
        # include metadata if searchable
        qlist if OpenTox::Authorization.is_token_valid(@subjectid)
        @u = []
        qlist.split.each{|u| @u << res = qfilter("isSummarySearchable", u) ? FourStore.query(params[:query].gsub(/WHERE \{/i, "FROM <#{u}> WHERE { ?s <#{RDF.type}> <http://onto.toxbank.net/isa/Investigation>. "), @accept) : FourStore.query(params[:query].gsub(/WHERE/i, "FROM <#{u}> WHERE"), @accept) }
        $logger.debug "@u:\n@accept:#{@accept}"
        @u
      else
        # returns uri-list, include searchable investigations
        response['Content-Type'] = 'text/uri-list'
        qlist if OpenTox::Authorization.is_token_valid(@subjectid)
      end
    end

    # Create a new investigation from ISA-TAB files
    # @param [Header] Content-type: multipart/form-data
    # @param file Zipped investigation files in ISA-TAB format
    # @return [text/uri-list] Task URI
    post '/investigation/?' do
      params[:id] = SecureRandom.uuid
      mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
      bad_request_error "No file uploaded." unless params[:file]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      if params[:file]
        if params[:file][:type] == "application/zip"
          bad_request_error "The zip #{params[:file][:filename]} contains no investigation file.", investigation_uri unless `unzip -Z -1 #{File.join(params[:file][:tempfile])}`.match('.txt')
        end
      end
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file][:filename]}: Uploading, validating and converting to RDF") do
        prepare_upload
        OpenTox::Authorization.create_pi_policy(investigation_uri, @subjectid)
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
        set_flag(RDF::TB.isPublished, false, "boolean")
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable] ? true : false), "boolean")
        #set_flag(RDF.Type, RDF::OT.Investigation)
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        investigation_uri
      end
      # TODO send notification to UI
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Get an investigation representation
    # @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
    # @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
    # include own and published
    get '/investigation/:id' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      case @accept
      when "text/tab-separated-values"
        send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
      when "text/uri-list"
        uri_list
      when "application/zip"
        send_file File.join dir, "investigation_#{params[:id]}.zip"
      else
        FourStore.query "CONSTRUCT { ?s ?p ?o } FROM <#{investigation_uri}> WHERE {?s ?p ?o}", @accept if is_pi?(@subjectid) || qfilter("isPublished") =~ /#{investigation_uri}/
      end
    end

    # Get investigation metadata in RDF
    # include own, pulished and searchable
    get '/investigation/:id/metadata' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      FourStore.query "CONSTRUCT { ?s ?p ?o.  } FROM <#{investigation_uri}> WHERE { ?s <#{RDF.type}> <http://onto.toxbank.net/isa/Investigation>. ?s ?p ?o .  } ", @accept if is_pi?(@subjectid) || qfilter("isSummarySearchable") =~ /#{investigation_uri}/ || qfilter("isPublished") =~ /#{investigation_uri}/
    end

    # Get a study, assay, data representation
    # @param [Header] one of text/tab-separated-values, application/sparql-results+json
    # @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
    # include own and published
    get '/investigation/:id/isatab/:filename'  do
      resource_not_found_error "File #{File.join investigation_uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
      # TODO: returns text/plain content type for tab separated files
      send_file file, :type => File.new(file).mime_type if is_pi?(@subjectid) || qfilter("isPublished") =~ /#{investigation_uri}/
    end

    # Get RDF for an investigation resource
    # include own and published
    get '/investigation/:id/:resource' do
      FourStore.query " CONSTRUCT {  <#{File.join(investigation_uri,params[:resource])}> ?p ?o.  } FROM <#{investigation_uri}> WHERE { <#{File.join(investigation_uri,params[:resource])}> ?p ?o .  } ", @accept if is_pi?(@subjectid) || qfilter("isPublished") =~ /#{investigation_uri}/
    end

    # Add studies, assays or data to an investigation
    # @param [Header] Content-type: multipart/form-data
    # @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
    # @return [text/uri-list] Task URI
    put '/investigation/:id' do
      if is_pi?(@subjectid)
        mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include?(params[:file][:type]) if params[:file] 
        task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{investigation_uri}: Add studies, assays or data.") do
          if params[:file]
            prepare_upload
            case params[:file][:type]
            when 'application/zip'
              extract_zip
            end
            isa2rdf
          end
          set_flag(RDF::TB.isPublished, (params[:published] ? true : false), "boolean") if params[:file] || (!params[:file] && params[:published])
          set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable] ? true : false), "boolean") if params[:file] || (!params[:file] && params[:summarySearchable])
          create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
          create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
          investigation_uri
        end
        # TODO send notification to UI
        response['Content-Type'] = 'text/uri-list'
        halt 202,task.uri+"\n"
      else
        bad_request_error "not authorized"
      end
    end

    # Delete an investigation
    delete '/investigation/:id' do
      if is_pi?(@subjectid)
        FileUtils.remove_entry dir
        # git commit
        `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{request.ip}"`
        # updata RDF
        FourStore.delete investigation_uri
        if @subjectid and !File.exists?(dir) and investigation_uri
          begin
            res = OpenTox::Authorization.delete_policies_from_uri(investigation_uri, @subjectid)
            $logger.debug "Policy deleted for Investigation URI: #{investigation_uri} with result: #{res}"
          rescue
            $logger.warn "Policy delete error for Investigation URI: #{investigation_uri}"
          end
        end
        # TODO send notification to UI
        response['Content-Type'] = 'text/plain'
        "Investigation #{params[:id]} deleted"
      else
        bad_request_error "not authorized"
      end
    end

    # Delete an individual study, assay or data file
    delete '/investigation/:id/:filename'  do
      if is_pi?(@subjectid)
        task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "Deleting #{params[:file][:filename]} from investigation #{params[:id]}.") do
          prepare_upload
          File.delete File.join(tmp,params[:filename])
          isa2rdf
          "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
        end
        # TODO send notification to UI
        response['Content-Type'] = 'text/uri-list'
        halt 202,task.uri+"\n"
      else
        bad_request_error "not authorized"
      end
    end

  end
end
