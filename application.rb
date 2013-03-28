require 'roo'
require 'opentox-server'
require_relative "tbaccount.rb"
require_relative "util.rb"

module OpenTox
  # full API description for ToxBank investigation service see:  
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service
  
    helpers do

      # @return investigation[:id] with full investigation service uri  
      def investigation_uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      # @return uri-list of files in investigation[:id] folder
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

      def nt
        "#{params[:id]}.nt"
      end

      def service_time timestring
        Time.parse(timestring).to_i
      end

      def delete_investigation_policy
        if @subjectid and !File.exists?(dir) and investigation_uri
          res = OpenTox::Authorization.delete_policies_from_uri(investigation_uri, @subjectid)
        end
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
        # TODO delete dir if task catches error, e.g. password locked, pass error to block
        if params[:file][:filename].match(/\.xls$|\.xlsx$/)
          xls = Excel.new(File.join(tmp, params[:file][:filename]))  if params[:file][:filename].match(/.xls$/)
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
        else
          FileUtils.remove_entry dir
          delete_investigation_policy
          bad_request_error "Could not parse spreadsheet #{params[:file][:filename]}"
        end
      end

      def isa2rdf
        # isa2rdf returns correct exit code but error in task
        # TODO delete dir if task catches error, pass error to block
        `cd #{File.dirname(__FILE__)}/java && java -jar isa2rdf-cli-0.0.4.jar -d #{tmp} -o #{File.join tmp,nt} -t #{$user_service[:uri]} `#&> #{File.join tmp,'log'}`
        # rewrite default prefix
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{investigation_uri}/;g' #{File.join tmp,nt}`
        investigation_id = `grep "#{investigation_uri}/I[0-9]" #{File.join tmp,nt}|cut -f1 -d ' '`.strip
        `sed -i 's;#{investigation_id.split.last};<#{investigation_uri}/>;g' #{File.join tmp,nt}`
        time = Time.new
        `echo '\n<#{investigation_uri}/> <#{RDF::DC.modified}> "#{time.strftime("%d %b %Y %H:%M:%S %Z")}" .' >> #{File.join tmp,nt}`
        `echo "\n<#{investigation_uri}/> <#{RDF.type}> <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,nt}`
        FileUtils.rm Dir[File.join(tmp,"*.zip")]
        # if everything is fine move ISA-TAB files back to original dir
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        # create new zipfile
        zipfile = File.join dir, "investigation_#{params[:id]}.zip"
        `zip -j #{zipfile} #{dir}/*.txt`
        # store RDF
        FourStore.put investigation_uri, File.read(File.join(dir,nt)), "application/x-turtle" # content-type not very consistent in 4store
        FileUtils.remove_entry tmp  # unlocks tmp
        # git commit
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files --others --exclude-standard --directory #{params[:id]}`
        `cd #{File.dirname(__FILE__)}/investigation && git add #{newfiles}`
        ['application/zip', 'application/vnd.ms-excel'].include?(params[:file][:type]) ? action = "created" : action = "modified"
        `cd #{File.dirname(__FILE__)}/investigation && git commit -am "investigation #{params[:id]} #{action} by #{OpenTox::Authorization.get_user(@subjectid)}"`
        investigation_uri
      end

      def create_policy ldaptype, uristring
        filename = File.join(dir, "#{ldaptype}_policies")
        policyfile = File.open(filename,"w")
        uriarray = uristring if uristring.class == Array
        uriarray = uristring.gsub(/[\[\]\"]/ , "").split(",") if uristring.class == String
        if uriarray.size > 0
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
        else
          Authorization.reset_policies investigation_uri, ldaptype, @subjectid
        end
      end

      def set_flag flag, value, type = ""
        flagtype = type == "boolean" ? "^^<#{RDF::XSD.boolean}>" : ""
        FourStore.update "DELETE DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}/> <#{flag}> \"#{!value}\"#{flagtype}}}"
        FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}/> <#{flag}> \"#{value}\"#{flagtype}}}"
      end

      # add or delete investigation_uri from search index at UI
      # @params[Boolean] true=add, false=delete
      def set_index inout=false
        OpenTox::RestClientWrapper.method(inout ? "put" : "delete").call "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => @subjectid}
      end

      # returns uri if related flag is set to "true"
      # @return [String] uri as string
      def qfilter(flag, uri)
        qfilter = FourStore.query "SELECT ?s FROM <#{uri}> WHERE {?s <#{RDF::TB}#{flag}> ?o FILTER regex(?o, 'true', 'i')}", "application/sparql-results+xml"
        $logger.debug "\ncheck flags: #{qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '').strip}\n"
        qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '').strip
      end

      def protected!(subjectid)
        if !env["session"] && subjectid
          unless !$aa[:uri] or $aa[:free_request].include?(env['REQUEST_METHOD'].to_sym)
            unless (request.env['REQUEST_METHOD'] != "GET" ? authorized?(subjectid) : get_permission)
              $logger.debug "URI not authorized for GET: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").sub("http://","https://").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
              unauthorized_error "Not authorized: #{request.env['REQUEST_URI']}"
            end
          end
        else
          unauthorized_error "Not authorized: #{request.env['REQUEST_URI']} for user: #{OpenTox::Authorization.get_user(subjectid)}"
        end
      end
      
      # @note manage Get requests with policies and flags
      def get_permission
        return false if request.env['REQUEST_METHOD'] != "GET"
        uri = to(request.env['REQUEST_URI'])
        curi = clean_uri(uri)
        return true if uri == $investigation[:uri]
        return true if OpenTox::Authorization.get_user(@subjectid) == "protocol_service"
        return true if OpenTox::Authorization.uri_owner?(curi, @subjectid)
        if (request.env['REQUEST_URI'] =~ /metadata/ ) || (request.env['REQUEST_URI'] =~ /protocol/ )
          return true if qfilter("isSummarySearchable", curi) =~ /#{curi}/
        end
        return true if OpenTox::Authorization.authorized?(curi, "GET", @subjectid) && qfilter("isPublished", curi) =~ /#{curi}/
        return false
      end

      def qlist mime_type
        list = FourStore.list mime_type
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
      if (@accept == "text/uri-list" || @accept == "application/rdf+xml") && !request.env['HTTP_USER']
        qlist @accept
      elsif (@accept == "application/rdf+xml" && request.env['HTTP_USER'])
        FourStore.query "CONSTRUCT {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation> }
        WHERE {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation>. ?investigation <#{RDF::TB}hasOwner> <#{request.env['HTTP_USER']}>}", @accept
      elsif (@accept == "application/json" && request.env['HTTP_USER'])
        response = FourStore.query "SELECT ?uri ?updated WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated}", @accept
        response.gsub(/(\d{2}\s[a-zA-Z]{3}\s\d{4}\s\d{2}\:\d{2}\:\d{2}\s[A-Z]{3})/){|t| service_time t}
      elsif (@accept == "text/uri-list" && request.env['HTTP_USER'])
        result = FourStore.query "SELECT ?uri WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated}", @accept
        result.split("\n").collect{|u| u.sub(/(\/)+$/,'')}.join("\n")
      else
        bad_request_error "Mime type: '#{@accept}' not supported with user: '#{request.env['HTTP_USER']}'."
      end
    end
    
    # Create a new investigation from ISA-TAB files
    # @param [Header] Content-type: multipart/form-data
    # @param file Zipped investigation files in ISA-TAB format
    # @return [text/uri-list] Task URI
    post '/investigation/?' do
      # CH: Task.create is now Task.run(description,creator_uri,subjectid) to avoid method clashes
      task = OpenTox::Task.run("#{params[:file] ? params[:file][:filename] : "no file attached"}: Uploading, validating and converting to RDF",to("/investigation"),@subjectid) do
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
            FileUtils.remove_entry dir
            delete_investigation_policy
            bad_request_error "The zip #{params[:file][:filename]} contains no investigation file."
          end
        end
        isa2rdf
        set_flag(RDF::TB.isPublished, false, "boolean")
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean")
        #set_flag(RDF.Type, RDF::OT.Investigation)
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
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
      # CH: Task.create is now Task.run(description,creator_uri,subjectid) to avoid method clashes
      task = OpenTox::Task.run("#{investigation_uri}: Add studies, assays or data.",@uri,@subjectid) do
        mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include?(params[:file][:type]) if params[:file] 
        bad_request_error "The zip #{params[:file][:filename]} contains no investigation file.", investigation_uri unless `unzip -Z -1 #{File.join(params[:file][:tempfile])}`.match('.txt') if params[:file]
        if params[:file]
          prepare_upload
          extract_zip if params[:file][:type] == 'application/zip'
          isa2rdf
        end
        set_flag(RDF::TB.isPublished, (params[:published].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:published])
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:summarySearchable])
        FourStore.update "WITH <#{investigation_uri}>
                          DELETE { <#{investigation_uri}/> <#{RDF::DC.modified}> ?o} WHERE {<#{investigation_uri}/> <#{RDF::DC.modified}> ?o};
                          INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}/> <#{RDF::DC.modified}> \"#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}\"}}"
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        curi = clean_uri(uri)
        if qfilter("isPublished", curi) =~ /#{curi}/ && qfilter("isSummarySearchable", curi) =~ /#{curi}/
          set_index true
        else
          set_index false
        end
        investigation_uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Delete an investigation
    delete '/investigation/:id' do
      set_index false
      FileUtils.remove_entry dir
      `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{OpenTox::Authorization.get_user(@subjectid)}"`
      FourStore.delete investigation_uri
      delete_investigation_policy
      response['Content-Type'] = 'text/plain'
      "Investigation #{params[:id]} deleted"
    end

=begin
    # Delete an individual study, assay or data file
    delete '/investigation/:id/:filename'  do
      # CH: Task.create is now Task.run(description,creator_uri,subjectid) to avoid method clashes
      task = OpenTox::Task.run("Deleting #{params[:file][:filename]} from investigation #{params[:id]}.",@uri,@subjectid) do
        prepare_upload
        File.delete File.join(tmp,params[:filename])
        isa2rdf
        set_index true if qfilter("isPublished", curi) =~ /#{curi}/ && qfilter("isSummarySearchable", curi) =~ /#{curi}/
        "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end
=end
  end
end
