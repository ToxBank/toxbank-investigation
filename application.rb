require 'roo'
require 'json'
require 'opentox-server'
require "#{File.dirname(__FILE__)}/tbaccount.rb"
require "#{File.dirname(__FILE__)}/util.rb"

module OpenTox
  class Application < Service

    helpers do

      # @return investigation[:id] with full investigation service uri  
      def investigation_uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      # @return uri-list of files in invetigation[:id] folder
      def uri_list 
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f| to(f.sub(/\.\//,'')) }
        uris.collect!{|u| u.sub(/(\/#{params[:id]}\/)/,'\1isatab/')} if params[:id]
        uris.delete_if{|u| u.match(/_policies$/)}
        uris.compact.sort.join("\n") + "\n"
      end

      # @return investigation dir path
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

      def service_time timestring
        $logger.debug "timestring from graph: #{timestring} "
        newtime = Time.parse(timestring)
        $logger.debug "new time object parsed: #{newtime}"
        $logger.debug "timestamp: #{newtime.to_i}"
        newtime.to_i
      end

      # @note copies investigation files in tmp folder 
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
        $logger.debug "\n#{params.inspect}\n"
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
          `cd #{File.dirname(__FILE__)}/java && java -jar isa2rdf-0.0.4-SNAPSHOT.jar -d #{tmp} -o #{File.join tmp,n3} -t #{$user_service[:uri]} &> #{File.join tmp,'log'}`
        rescue
          log = File.read File.join(tmp,"log")
          FileUtils.remove_entry dir
          bad_request_error "ISA-TAB validation failed:\n#{log}", investigation_uri
        end
        # rewrite default prefix
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{investigation_uri}/;' #{File.join tmp,n3}`
        investigation_id = `grep ":I[0-9]" #{File.join tmp,n3}|cut -f1 -d ' '`.strip
        `sed -i 's;#{investigation_id};:;' #{File.join tmp,n3}`
        time = Time.new
        #`echo '\n: <#{RDF::DC.modified}> "#{Time.new}" .' >> #{File.join tmp,n3}`
        `echo '\n: <#{RDF::DC.modified}> "#{time.strftime("%d %b %Y %H:%M:%S %Z")}" .' >> #{File.join tmp,n3}`
        `echo "\n: a <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,n3}`
        FileUtils.rm Dir[File.join(tmp,"*.zip")]
        # if everything is fine move ISA-TAB files back to original dir
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        # create new zipfile
        zipfile = File.join dir, "investigation_#{params[:id]}.zip"
        `zip -j #{zipfile} #{dir}/*.txt`
        # store RDF
        FourStore.put investigation_uri, File.read(File.join(dir,n3)), "text/turtle" # content-type not very consistent in 4store
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
          #uriarray = uristring.split(",")
          uriarray = uristring if uristring.class == Array
          uriarray = uristring.gsub(/[\[\]\"]/ , "").split(",") if uristring.class == String
          return 0 if uriarray.size < 1
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

      # returns uri if related flag is set to "true"
      # @return [String] uri as string
      def qfilter(flag, uri)
        qfilter = FourStore.query "SELECT ?s FROM <#{uri}> WHERE {?s <#{RDF::TB}#{flag}> ?o FILTER regex(?o, 'true', 'i')}", "application/sparql-results+xml"
        qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '').strip
      end

      def protected!(subjectid)
        if !env["session"] && subjectid
          unless !$aa[:uri] or $aa[:free_request].include?(env['REQUEST_METHOD'].to_sym)
            unless (request.env['REQUEST_METHOD'] != "GET" ? authorized?(subjectid) : get_permission)
              $logger.debug ">-get_permission failed"
              $logger.debug "URI not authorized: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").sub("http://","https://").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
              unauthorized_error "Not authorized: #{request.env['REQUEST_URI']}"
            end
          end
        else
          unauthorized_error "Not authorized: #{request.env['REQUEST_URI']}"
        end
      end
      
      # @note manage Get requests with policies and flags
      def get_permission
        # only for GET
        return false if request.env['REQUEST_METHOD'] != "GET"
        uri = to(request.env['REQUEST_URI'])
        curi = clean_uri(uri)
        return true if uri == $investigation[:uri]
        return true if OpenTox::Authorization.get_user(@subjectid) == "protocol_service"
        # GET request without policy check
        if OpenTox::Authorization.uri_owner?(curi, @subjectid)
          return true
        elsif request.env['REQUEST_URI'] =~ /metadata/
          return true if qfilter("isSummarySearchable", curi) =~ /#{curi}/
        # Get request with policy and flag check 
        else
          return true if OpenTox::Authorization.authorized?(curi, "GET", @subjectid) && qfilter("isPublished", curi) =~ /#{curi}/
        end
        return false
      end

      def qlist
        list = FourStore.list "text/uri-list"
        service_uri = to("/investigation")
        list.split.keep_if{|v| v =~ /#{service_uri}/}.join("\n")# show all, ignore flags
      end

    end

    before do
      $logger.debug "WHO: #{OpenTox::Authorization.get_user(@subjectid)}, request method: #{request.env['REQUEST_METHOD']}, type: #{request.env['CONTENT_TYPE']}\n\nhole request env: #{request.env}\n\nparams inspect: #{params.inspect}\n\n"
      resource_not_found_error "Directory #{dir} does not exist."  unless File.exist? dir
      parse_input if request.request_method =~ /POST|PUT/
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
    end

    # head request
    head '/investigation/?' do
    end
    
    # uri-list of all investigations or user uris
    # @return [text/uri-list, application/rdf+xml, application/json] List of investigations
    # @note return all investigations, ignoring flags
    get '/investigation/?' do
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/uri-list, application/json or application/rdf+xml." unless (@accept.to_s == "text/uri-list") || (@accept.to_s == "application/rdf+xml") || (@accept.to_s == "application/json")
      case @accept
      when "text/uri-list"
        qlist
      else
        # return uri-list of users investigations
        # rdf+xml
        if (@accept == "application/rdf+xml" && request.env['HTTP_USER'])
          FourStore.query "CONSTRUCT {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation> }
          WHERE {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation>. ?investigation <#{RDF::TB}hasOwner> <#{request.env['HTTP_USER']}>}", @accept
        # application/json
        # for UI
        elsif (@accept == "application/json" && request.env['HTTP_USER'])
          response = FourStore.query "SELECT ?uri ?updated WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated}", @accept
          response.gsub(/(\d{2}\s[a-zA-Z]{3}\s\d{4}\s\d{2}\:\d{2}\:\d{2}\s[A-Z]{3})/){|t| service_time t}
        end
      end
    end
    
    # Create a new investigation from ISA-TAB files
    # @param [Header] Content-type: multipart/form-data
    # @param file Zipped investigation files in ISA-TAB format
    # @return [text/uri-list] Task URI
    post '/investigation/?' do
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file] ? params[:file][:filename] : "no file attached"}: Uploading, validating and converting to RDF") do
        params[:id] = SecureRandom.uuid
        mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
        bad_request_error "No file uploaded." unless params[:file]
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
        prepare_upload
        OpenTox::Authorization.create_pi_policy(investigation_uri, @subjectid)
        case params[:file][:type]
        when "application/vnd.ms-excel"
          extract_xls
        when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          extract_xls
        when 'application/zip'
          if `unzip -Z -1 #{File.join(params[:file][:tempfile])}`.match('.txt')
            extract_zip
          else
            FileUtils.remove_dir dir
            bad_request_error "The zip #{params[:file][:filename]} contains no investigation file.", investigation_uri
          end
        #when  'text/tab-separated-values' # do nothing, file is already in tmp
        end
        isa2rdf
        set_flag(RDF::TB.isPublished, false, "boolean")
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean")
        #set_flag(RDF.Type, RDF::OT.Investigation)
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        # send notification to UI
        OpenTox::RestClientWrapper.put "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => @subjectid}
        investigation_uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Get an investigation representation
    # @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/rdf+xml
    # @return [text/tab-separated-values, text/uri-list, application/zip, application/rdf+xml] Investigation in the requested format
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
        FourStore.query "CONSTRUCT { ?s ?p ?o } FROM <#{investigation_uri}> WHERE {?s ?p ?o}", @accept
      end
    end

    # Get investigation metadata
    # @param [Header] Accept: one of text/plain, text/turtle, application/rdf+xml
    # @return [text/plain, text/turtle, application/rdf+xml]
    # include own, pulished and searchable
    get '/investigation/:id/metadata' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      FourStore.query "CONSTRUCT { ?s ?p ?o.  } FROM <#{investigation_uri}> 
      WHERE { ?s <#{RDF.type}> <#{RDF::ISA}Investigation>. ?s ?p ?o .  } ", @accept
    end

    # Get investigation protocol uri
    get '/investigation/:id/protocol' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      FourStore.query "CONSTRUCT {?study <#{RDF::ISA}hasProtocol> ?protocol. ?protocol <#{RDF.type}> <#{RDF::TB}Protocol>.} 
      FROM <#{investigation_uri}> 
      WHERE {<#{investigation_uri}/> <#{RDF::ISA}hasStudy> ?study. ?study <#{RDF::ISA}hasProtocol> ?protocol. ?protocol <#{RDF.type}> <#{RDF::TB}Protocol>.}", @accept
    end

    # Get a study, assay, data representation
    # @param [Header] Accept: one of text/tab-separated-values, application/sparql-results+json
    # @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
    # @note include own and published
    get '/investigation/:id/isatab/:filename'  do
      resource_not_found_error "File #{File.join investigation_uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
      # TODO: returns text/plain content type for tab separated files
      send_file file, :type => File.new(file).mime_type
    end

    # Get RDF for an investigation resource
    # @param [Header] Accept: one of text/plain, text/turtle, application/rdf+xml
    # @return [text/plain, text/turtle, application/rdf+xml]
    # @note include own and published
    get '/investigation/:id/:resource' do
      FourStore.query " CONSTRUCT {  <#{File.join(investigation_uri,params[:resource])}> ?p ?o.  } FROM <#{investigation_uri}> WHERE { <#{File.join(investigation_uri,params[:resource])}> ?p ?o .  } ", @accept
    end

    # Add studies, assays or data to an investigation
    # @param [Header] Content-type: multipart/form-data
    # @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
    # @return [text/uri-list] Task URI
    put '/investigation/:id' do
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{investigation_uri}: Add studies, assays or data.") do
        mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include?(params[:file][:type]) if params[:file] 
        bad_request_error "The zip #{params[:file][:filename]} contains no investigation file.", investigation_uri unless `unzip -Z -1 #{File.join(params[:file][:tempfile])}`.match('.txt') if params[:file]
        if params[:file]
          prepare_upload
          case params[:file][:type]
          when 'application/zip'
            extract_zip
          end
          isa2rdf
        end
        set_flag(RDF::TB.isPublished, (params[:published].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:published])
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:summarySearchable])
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        # send notification to UI
        OpenTox::RestClientWrapper.put "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => @subjectid}
        investigation_uri
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
      FourStore.delete investigation_uri
      if @subjectid and !File.exists?(dir) and investigation_uri
        res = OpenTox::Authorization.delete_policies_from_uri(investigation_uri, @subjectid)
        $logger.debug "Policy deleted for Investigation URI: #{investigation_uri} with result: #{res}"
      end
      # TODO send notification to UI
      OpenTox::RestClientWrapper.delete "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => @subjectid}
      response['Content-Type'] = 'text/plain'
      "Investigation #{params[:id]} deleted"
    end

    # Delete an individual study, assay or data file
    delete '/investigation/:id/:filename'  do
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "Deleting #{params[:file][:filename]} from investigation #{params[:id]}.") do
        prepare_upload
        File.delete File.join(tmp,params[:filename])
        isa2rdf
        # TODO send notification to UI (TO CHECK: if files will be indexed?)
        # OpenTox::RestClientWrapper.put "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => @subjectid}
        
        "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

  end
end
