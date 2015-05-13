require 'opentox-server'
require_relative "tbaccount.rb"
require_relative "util.rb"
require_relative "helper.rb"
require_relative "helper_isatab.rb"
require_relative "helper_unformatted.rb"
# ToxBank implementation based on OpenTox API and OpenTox ruby gems

module OpenTox
  # For full API description of the ToxBank investigation service see:
  # {http://api.toxbank.net/index.php/Investigation ToxBank API Investigation}
  class Application < Service

    helpers do
      include Helpers
      # overwrite opentox-server method for toxbank use
      # @see {http://api.toxbank.net/index.php/Investigation#Security API: Investigation Security}
      def protected!(subjectid)
        if !env["session"] && subjectid
          unless !$aa[:uri] or $aa[:free_request].include?(env['REQUEST_METHOD'].to_sym)
            unless (request.env['REQUEST_METHOD'] != "GET" ? authorized?(subjectid) : get_permission)
              $logger.debug "URI not authorized for GET: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").sub("http://","https://").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
              unauthorized_error "Not authorized: #{request.env['REQUEST_URI']}"
            end
          end
        else
          unauthorized_error "Not authorized: #{request.env['REQUEST_URI']} for user: #{OpenTox::Authorization.get_user}"
        end
      end
    end

    before do
      $logger.debug "WHO: #{OpenTox::Authorization.get_user}, request method: #{request.env['REQUEST_METHOD']}, type: #{request.env['CONTENT_TYPE']}\n\nhole request env: #{request.env}\n\nparams inspect: #{params.inspect}\n\n"
      resource_not_found_error "Directory #{dir} does not exist."  unless File.exist? dir
      #parse_input if request.request_method =~ /POST|PUT/
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
    end

    # @!group URI Routes

    # @method head_all
    # @overload head "/investigation/?"
    # Head request.
    # @return [String] only HTTP headers.
    head '/investigation/?' do
    end


    # @method get_all
    # @overload get "/investigation/?"
    # List URIs of all investigations or investigations of a user.
    # @param header [hash]
    #   * Accept [String] <text/uri-list, application/rdf+xml, application/json>
    #   * subjectid [String] authorization token
    # @return [String] text/uri-list, application/rdf+xml, application/json List of investigations.
    # @raise [BadRequestError] if wrong mime-type
    # @see http://api.toxbank.net/index.php/Investigation#Get_a_list_of_investigations API: Get a list of investigations
    get '/investigation/?' do
      mime_types = ['text/uri-list', 'application/rdf+xml', 'application/json']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/uri-list, application/json or application/rdf+xml." unless mime_types.include? @accept
      if (@accept == "text/uri-list" && !request.env['HTTP_USER'])
        qlist @accept
      elsif (@accept == "application/rdf+xml" && !request.env['HTTP_USER'])
        FourStore.query "CONSTRUCT {?s <#{RDF.type}> <#{RDF::ISA}Investigation> } WHERE { ?s <#{RDF.type}> <#{RDF::ISA}Investigation>.}", @accept
      elsif (@accept == "application/rdf+xml" && request.env['HTTP_USER'])
        FourStore.query "CONSTRUCT {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation> }
        WHERE {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation>. ?investigation <#{RDF::TB}hasOwner> <#{request.env['HTTP_USER']}>}", @accept
      elsif (@accept == "application/json" && request.env['HTTP_USER'])
        response = FourStore.query "SELECT ?uri ?updated WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated  FILTER regex(?updated, \"[A-Z]{3}$\")}", @accept
        # get timestring and parse to timestamp {3,4} for different zones
        response.gsub(/(\d{2}\s[a-zA-Z]{3}\s\d{4}\s\d{2}\:\d{2}\:\d{2}\s[A-Z]{3,4})/){|t| get_timestamp t}
      elsif (@accept == "text/uri-list" && request.env['HTTP_USER'])
        result = FourStore.query "SELECT ?uri WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated}", @accept
        result.split("\n").collect{|u| u.sub(/(\/)+$/,'')}.join("\n")
      else
        bad_request_error "Mime type: '#{@accept}' not supported with user: '#{request.env['HTTP_USER']}'."
      end
    end

    # @method get_ftpfiles
    # @overload get "/investigation/ftpfiles/?"
    # List all uploaded FTP-files of a user.
    # @param header [hash]
    #   * Accept [String] <text/uri-list, application/json>
    #   * subjectid [String] authorization token
    # @return [String] text/uri-list, application/json List of files.
    # @raise [BadRequestError] if wrong mime-type
    # @see http://api.toxbank.net/index.php/Investigation#Get_a_list_of_uploaded_files API: Get a list of investigations
    get '/investigation/ftpfiles/?' do
       bad_request_error "Mime type #{@accept} not supported here. Please request data as text/uri-list or application/json." unless (@accept.to_s == "text/uri-list") || (@accept.to_s == "application/json")
       filehash = get_ftpfiles
       user = Authorization.get_user
       case @accept.to_s
        when "application/json"
          return JSON.pretty_generate( {"head"=>{"vars" => ["filename","basename"]},"results"=> {"bindings"=>filehash.collect{|fullname, basename| {"filename"=>{"type"=>"string", "value"=> fullname.gsub("/home/ftpusers/#{user}/","")}, "basename"=>{"type"=>"string", "value"=> basename}}}}} )
        when "text/uri-list"
          return filehash.collect{|fullname,basename| "#{fullname.gsub("/home/ftpusers/#{user}/","")}\n"}
        else
          return filehash
        end
    end

    # @method post_investigation
    # @overload post "/investigation/?"
    # Create a new investigation from ISA-TAB files.
    # @param header [Hash]
    #   * Accept [String] <'multipart/form-data'>
    #   * subjectid [String] authorization token
    # @param [File] Zipped investigation files in ISA-TAB format.
    # @return [String] text/uri-list Task URI.
    # @raise [BadRequestError] without file upload and wrong mime-type.
    # @see http://api.toxbank.net/index.php/Investigation#Create_an_investigation API: Create an investigation
    post '/investigation/?' do
      # CH: Task.create is now Task.run(description,creator_uri,subjectid) to avoid method clashes
      params[:id] = SecureRandom.uuid
      task = OpenTox::Task.run("#{params[:file] ? params[:file][:filename] : "no file attached"}: Uploading, validating and converting to RDF",to("/investigation")) do
        #params[:id] = SecureRandom.uuid
        mime_types = ['application/zip','text/tab-separated-values']
        inv_types = ['noData', 'unformattedData', 'ftpData']
        # no data or ftp data
        if params[:type] && !params[:file]
          bad_request_error "Investigation type '#{params[:type]}' not supported." unless inv_types.include? params[:type]
          case params[:type]
          when "noData"
            bad_request_error "Parameter 'ftpData' not expected for type '#{params[:type]}'." if params[:ftpFile]
            clean_params "noftp"
            OpenTox::Authorization.create_pi_policy(investigation_uri)
            prepare_upload
            params2rdf
          when "ftpData"
            clean_params "ftp"
            OpenTox::Authorization.create_pi_policy(investigation_uri)
            prepare_upload
            link_ftpfiles_by_params
            params2rdf
          end
        # unformated data
        elsif params[:type] && params[:file]
          bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip)." unless mime_types[0] == params[:file][:type]
          bad_request_error "Investigation type '#{params[:type]}' not supported." unless inv_types.include? params[:type]
          bad_request_error "No file expected for type '#{params[:type]}'." unless params[:type] == "unformattedData"
          bad_request_error "File '#{params[:file][:filename]}' is to large. Please choose FTP investigation type and upload to your FTP directory first." unless (params[:file][:tempfile].size.to_i < 10485760)
          clean_params "noftp"
          OpenTox::Authorization.create_pi_policy(investigation_uri)
          prepare_upload
          params2rdf
        # isa-tab data
        elsif params[:file] && !params[:type]
          bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
          OpenTox::Authorization.create_pi_policy(investigation_uri)
          case params[:file][:type]
          when 'application/zip'
            prepare_upload
            extract_zip
            isa2rdf
          end
        # no params or data
        else
          bad_request_error "No file uploaded or parameters given."
        end
        # set flags and modified date
        set_flag(RDF::TB.isPublished, false, "boolean")
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean")
        set_modified
        # set access rules
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        investigation_uri
      end
      # remove unformatted investigation if import error
      begin
        t = OpenTox::Task.new task.uri
        t.wait
        if t.hasStatus == "Error"
          $logger.debug "Error in POST: #{investigation_uri} remove dir."
          FileUtils.remove_entry dir if Dir.exist?(dir)
          `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{OpenTox::Authorization.get_user}"` if `cd #{File.dirname(__FILE__)}/investigation; git diff` != ""
          FourStore.delete investigation_uri
          delete_investigation_policy
        end
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # @method get_sparql
    # @overload get "/investigation/sparql/:templatename"
    # Get data by predefined SPARQL templates for investigations
    # @param [Hash] header
    #   * Accept [String] <application/sparql-results+xml, application/json, text/uri-list, text/html>
    #   * subjectid [String] authorization token
    # @return [String] sparql-results+xml, json, uri-list, html
    get '/investigation/sparql/:templatename' do
      bad_request_error "Mime type #{@accept} not supported here. Please request data as 'application/json'." unless (@accept.to_s == "application/json")
      templates = get_templates ""
      templatename = params[:templatename].underscore
      resource_not_found_error "Template: #{params[:templatename]} does not exist."  unless templates.has_key? templatename
      bad_request_error "relational operator not expected." if params[:relOperator] and templatename !~ /_by_gene_and_value$/
      case templatename
      when /^biosearch$/
        genes = params[:geneIdentifiers].gsub(/[\[\]\"]/ , "").split(",")
        if genes.class == Array
          VArr = []
          genes.each do |gene|
            VArr << "{ ?dataentry skos:closeMatch #{gene.gsub("'","").strip}. }" unless gene.empty?
          end
          sparqlstring = File.read(File.join File.dirname(File.expand_path __FILE__), "template/biosearch.sparql") % { :Values => VArr.join(" UNION ") }
        else
          sparqlstring = File.read(File.join File.dirname(File.expand_path __FILE__), "template/biosearch.sparql") % { :Values => "{ ?dataentry skos:closeMatch #{values.gsub("'","").strip}. }" }
        end
        response = FourStore.query sparqlstring, "application/json"
        @a = JSON.parse(check_get_access response)
        @a["head"]["vars"] << "factorvalues"
        @a["head"]["vars"] << "characteristics"
        datanodes = @a["results"]["bindings"].map{|n| n["data"]["value"] }.uniq
        
        # collect factorvalues with biosamples by datanode
        sparqlstring = File.read(File.join File.dirname(File.expand_path __FILE__), "template/biosearch2.sparql") % { :data => datanodes[0]}
        response = FourStore.query sparqlstring, "application/json"
        @b = JSON.parse(response)
        @biosamples = @b["results"]["bindings"].map{|n| n["biosample"]["value"]}.uniq
        #@a["results"]["bindings"].find{|n| n["data"]["value"] == datanodes[0]}["factorvalues"] ||= @b["results"]["bindings"] 
        datanodes.each_with_index{|d,idx| @a["results"]["bindings"].find{|n| n["data"]["value"] == d}["factorvalues"] ||= @b["results"]["bindings"][idx]}
        
        # collect characteristics by biosample
        sparqlstring = File.read(File.join File.dirname(File.expand_path __FILE__), "template/biosearch3.sparql") % { :sample_uri => @biosamples[0]}
        response = FourStore.query sparqlstring, "application/json"
        @c = JSON.parse(response)
        @a["results"]["bindings"].find{|n| n["factorvalues"]}["characteristics"] ||= @c["results"]["bindings"]
        
        # paste characteristics
        @a["results"]["bindings"].find{|n| n["factorvalues"]}["characteristics"] ||= @characteristics
        
        #clean up
        @a["head"]["vars"].delete("data")
        @a["results"]["bindings"].each{|n| n.delete("data")}
        
        # parse for output
        JSON.pretty_generate(@a)
      when /_by_gene_and_value$/
        bad_request_error "missing parameter geneIdentifiers. '#{params[:geneIdentifiers]} is not a valid gene identifier." if params[:geneIdentifiers].blank? || params[:geneIdentifiers] !~ /.*\:.*/
        bad_request_error "missing relational operator 'above' or 'below' ." if params[:relOperator].blank? || params[:relOperator] !~ /^above$|^below$/
        bad_request_error "missing parameter value. Request needs a value." if params[:value].blank?
        bad_request_error "missing parameter value_type. Request needs a value_type like 'FC:0.7'." if params[:value].to_s !~ /.*\:.*/
        bad_request_error "wrong parameter value_type. Request needs a value_type like 'FC,pvalue,qvalue'." if params[:value].split(":").first !~ /^FC$|^pvalue$|^qvalue$/

        #if params[:relOperator].blank?
        #  relOperator = "<="
        #else
        #  relOperator = params[:relOperator] =~ /above/ ? ">=" : "<="
        #end
        relOperator = params[:relOperator] =~ /above/ ? ">=" : "<="
        genes = params[:geneIdentifiers].gsub(/[\[\]\"]/ , "").split(",")
        # split params[:value] in "value_type" and "value"
        value_type = "http://onto.toxbank.net/isa/" + params[:value].split(":").first
        value = params[:value].split(":").last
        if genes.class == Array
          VArr = []
          genes.each do |gene|
            VArr << "{ ?dataentry skos:closeMatch #{gene.gsub("'","").strip}. }" unless gene.empty?
          end
          sparqlstring = File.read(templates[templatename]) % { :Values => VArr.join(" UNION "), :value_type => value_type, :value => value, :relOperator => relOperator }
        else
          sparqlstring = File.read(templates[templatename]) % { :Values => "{ ?dataentry skos:closeMatch #{values.gsub("'","").strip}. }", :value_type => value_type, :value => value, :relOperator => relOperator }
        end
        $logger.debug sparqlstring
        result = FourStore.query sparqlstring, "application/json"
        check_get_access result
      when /^genelist/
        response = FourStore.query File.read(templates[templatename]) , "application/json"
        result = (check_get_access response)
        out = JSON.parse(result)
        out["head"]["vars"].delete_if{|i| i == "investigation"}
        out["results"]["bindings"].each{|node| node.delete_if{|i| i == "investigation"}}
        out["results"]["bindings"].uniq!
        JSON.pretty_generate(out)
      when /_and_/
        result = FourStore.query File.read(templates[templatename]) , "application/json"
        check_get_access result
      when /_by_[a-z]+s$/
        genesparql = templatename.match(/_by_genes$/)
        params[:geneIdentifiers].split(",").each{|gene| bad_request_error "'#{gene}' is not a valid gene identifier." if gene !~ /.*\:.*/} if params[:geneIdentifiers]
        values = genesparql ? params[:geneIdentifiers] : params[:factorValues]
        bad_request_error "missing parameter #{genesparql ? "geneIdentifiers": "factorValues"}. Request needs one or multiple(separated by comma)." if values.blank?
        values = values.gsub(/[\[\]\"]/ , "").split(",") if values.class == String
        VArr = []
        if templatename.match(/_by_factors$/)
          values.each do |value|
            VArr << "{ ?factorValue isa:hasOntologyTerm <#{value.gsub("'","").strip}>. }"
          end
        else
          values.each do |value|
            VArr << (genesparql ? "{ ?dataentry skos:closeMatch #{value.gsub("'","").strip}. }" :  "{ ?value isa:hasOntologyTerm <#{value.gsub("'","").strip}>. }")
          end
        end
        sparqlstring = File.read(templates[templatename]) % { :Values => VArr.join(" UNION ") }
        result = FourStore.query sparqlstring, "application/json"
        check_get_access result
      when /_by_[a-z_]+(?<!s)$/
        bad_request_error "missing parameter value. Request needs a value." if params[:value].blank?
        sparqlstring = File.read(templates[templatename]) % { :value => params[:value] }
        result = FourStore.query sparqlstring, "application/json"
        check_get_access result
      else
        not_implemented_error "Template: #{params[:templatename]} is not implemented yet."
      end
    end

    # @method get_id
    # @overload get "/investigation/:id"
    # Get an investigation representation.
    # @param [Hash] header
    #   * Accept [String] <text/tab-separated-values, text/uri-list, application/zip, application/rdf+xml>
    #   * subjectid [String] authorization token
    # @return [String] text/tab-separated-values, text/uri-list, application/zip, application/rdf+xml - Investigation in the requested format.
    # @raise [ResourceNotFoundError] if directory didn't exists
    # @see http://api.toxbank.net/index.php/Investigation#Get_an_investigation_representation API: Get an investigation representation
    get '/investigation/:id' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      mime_types = ['text/tab-separated-values', 'text/uri-list', 'application/zip', 'application/rdf+xml']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/tab-separated-values, text/uri-list, application/zip or application/rdf+xml." unless mime_types.include? @accept
      case @accept
      when "text/tab-separated-values"
        invfile = Dir["#{dir}/i_*.txt"][0]
        resource_not_found_error "Investigation is not in ISA-TAB format. Please request metadata for details." if invfile.blank?
        send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
      when "text/uri-list"
        uri_list
      when "application/zip"
        resource_not_found_error "Investigation zip does not exist. Please request application/rdf+xml."  unless File.exist? File.join(dir, "investigation_#{params[:id]}.zip")
        send_file File.join dir, "investigation_#{params[:id]}.zip"
      else
        # application/rdf+xml
        FourStore.query "CONSTRUCT { ?s ?p ?o } FROM <#{investigation_uri}> WHERE {?s ?p ?o}", @accept
      end
    end

    # @method get_dashboard
    # @overload get "/investigation/:id/dashboard"
    # Get investigation dashboard values.
    # @param [Hash] header
    #   * Accept [String] <application/json>
    #   * subjectid [String] authorization token
    # @return [Array] application/json.
    # @see http://api.toxbank.net/index.php/Investigation#Get_investigation_data_for_dashboard_contents API: Get investigation data for dashboard contents
    get '/investigation/:id/dashboard' do
      bad_request_error "Mime type #{@accept} not supported here. Please request data as application/json." unless (@accept.to_s == "application/json")
      bad_request_error "No dashboard content available." unless is_isatab?
      response['Content-Type'] = 'application/json'
      get_cache
    end

    # @method get_metadata
    # @overload get "/investigation/:id/metadata"
    # Get investigation metadata.
    # @param [Hash] header
    #   * Accept [String] <text/plain, text/turtle, application/rdf+xml>
    #   * subjectid [String] authorization token
    # @return [String] text/plain, text/turtle, application/rdf+xml.
    # @see http://api.toxbank.net/index.php/Investigation#Get_investigation_metadata API: Get investigation metadata
    get '/investigation/:id/metadata' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      mime_types = ['text/plain', 'text/turtle', 'application/rdf+xml']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/plain, text/turtle or application/rdf+xml." unless mime_types.include? @accept
      FourStore.query "CONSTRUCT {?s ?p ?o.} 
                       FROM <#{investigation_uri}>
                       WHERE {?s <#{RDF.type}> <#{RDF::ISA}Investigation>.
                       OPTIONAL {?s <http://purl.org/dc/terms/license> ?o.}
                              ?s ?p ?o . 
                       } ", @accept
    end

    # @method get_protocol
    # @overload get "/investigation/:id/protocol"
    # Get investigation protocol uri
    # @raise [ResourceNotFoundError] if file do not exist
    # @return [String] text/plain, text/turtle, application/rdf+xml
    # @see http://api.toxbank.net/index.php/Investigation#Get_a_protocol_uri_associated_with_a_Study API: Get a protocol uri associated with a
    get '/investigation/:id/protocol' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      mime_types = ['text/plain', 'text/turtle', 'application/rdf+xml']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/plain, text/turtle or application/rdf+xml." unless mime_types.include? @accept
      FourStore.query "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
                       PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
                       CONSTRUCT {?study <#{RDF::ISA}hasProtocol> ?protocol.
                                  ?protocol a ?type.
                                  ?protocol rdfs:label ?label.
                       }
                       FROM <#{investigation_uri}>
                       WHERE {<#{investigation_uri}> <#{RDF::ISA}hasStudy> ?study.
                       ?study <#{RDF::ISA}hasProtocol> ?protocol.
                       ?protocol a ?type.
                       OPTIONAL { ?protocol rdfs:label ?label.}
                       }", @accept
    end

    # @method get_subtaskuri
    # @overload get "/investigation/:id/subtaskuri"
    # Get SubTaskURI of an investigation.
    # @param [Hash] header
    #   * Accept [String] <text/uri-list, application/json>
    #   * subjectid [String] authorization token
    # Returns the URI of an data subtask or an empty string if requested with 'text/uri-list'
    # @raise [ResourceNotFoundError] if investigation URI do not exist.
    # @return [String] text/uri-list  or application/json.
    get '/investigation/:id/subtaskuri' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir
      mime_types = ['text/uri-list', 'application/json']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/uri-list or application/json." unless mime_types.include? @accept
      FourStore.query "SELECT ?subtaskuri WHERE { <#{investigation_uri}> <#{RDF::TB.hasSubTaskURI}> ?subtaskuri. }", @accept
    end

    # @method get_file
    # @overload get "/investigation/:id/:filename"
    # Get a study, assay, data representation
    # @param [Hash] header
    #   * Accept [String] <text/tab-separated-values, application/sparql-results+json>
    #   * subjectid [String] authorization token
    # @return [String] of mime-type [text/tab-separated-values] - Study, assay, data representation in ISA-TAB or RDF format.
    # @see http://api.toxbank.net/index.php/Investigation#Get_a_study.2C_assay_or_data_representation API: Get a study, assay or data representation
    ['/investigation/:id/isatab/:filename','/investigation/:id/files/:filename'].each do |path|
      get path do
        resource_not_found_error "File #{File.join investigation_uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
        filetype = (File.symlink?(file) ? File.new(File.readlink(file)).mime_type : File.new(file).mime_type)
        #TODO set mime-type for isatab ?
        # send_file file, :type => (request.path =~ /isatab/) ? 'text/tab-separated-values' : filetype
        send_file file, :type => filetype
      end
    end
    
    # @method get_resource
    # @overload get "/investigation/:id/:recource"
    # Get n-triples, turtle or RDF for an investigation resource
    # @param [Hash] header
    #   * Accept [String] <text/plain, text/turtle, application/rdf+xml>
    #   * subjectid [String] authorization token
    # @return [String] text/plain, text/turtle, application/rdf+xml
    # @note Result includes your own and published investigations.
    get '/investigation/:id/:resource' do
      resource_not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir
      mime_types = ['text/plain', 'text/turtle', 'application/rdf+xml']
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/plain, text/turtle or application/rdf+xml." unless mime_types.include? @accept
      result = FourStore.query " CONSTRUCT {  <#{File.join(investigation_uri,params[:resource])}> ?p ?o.  } FROM <#{investigation_uri}> WHERE { <#{File.join(investigation_uri,params[:resource])}> ?p ?o .  } ", @accept
      result.blank? ? "Resource '#{params[:resource]}' not found.\n" : result
    end

    # @method get_investigation_sparql
    # @overload get "/investigation/:id/sparql/:templatename"
    # Get data by predefined SPARQL templates for an investigation resource
    # @param [Hash] header
    #   * Accept [String] <application/sparql-results+xml, application/json, text/uri-list, text/html>
    #   * subjectid [String] authorization token
    # @return [String] sparql-results+xml, json, uri-list, html
    ['/investigation/:id/sparql/:templatename', '/investigation/:id/sparql/:templatename/:biosample'].each do |path|
      get path do
        templates = get_templates "investigation"
        templatename = params[:templatename].underscore
        $logger.debug "templatename:\t#{templatename}"
        resource_not_found_error "Template: #{params[:templatename]} does not exist."  unless templates.has_key? templatename
        unless templatename == "characteristics_by_sample"
          sparqlstring = File.read(templates[templatename]) % { :investigation_uri => investigation_uri }
        else
          sparqlstring = File.read(templates[templatename]) % { :sample_uri => investigation_uri + "/" + params[:biosample] }
        end
        FourStore.query sparqlstring, @accept
      end
    end

    # @method put_id
    # @overload put "/investigation/:id"
    # Add studies, assays or data to an investigation. Send as *Content-type* multipart/form-data
    # @param [Hash] header * subjectid [String] authorization token
    # @param [Hash] params
    #   * allowReadByUser [String] one or multiple userservice-URIs (User)
    #   * allowReadByGroup [String] one or multiple userservice-URIs (Organisations, Projects)
    #   * summarySearchable [String] true/false (default is false)
    #   * published true/false [String] (default is false)
    # @param [File] Zipped investigation files in ISA-TAB format.
    # @return [String] text/uri-list Task URI
    # @see http://api.toxbank.net/index.php/Investigation#Add.2Fupdate_studies.2C_assays_or_data_to_an_investigation API: Add/update studies, assays or data to an investigation
    # @see http://api.toxbank.net/index.php/User API: User service
    put '/investigation/:id' do
      task = OpenTox::Task.run("#{investigation_uri}: Add studies, assays or data.",@uri) do
        mime_types = ['application/zip','text/tab-separated-values']
        inv_types = ['noData', 'unformattedData', 'ftpData']
        param_types = ['title', 'abstract', 'owningOrg', 'owningPro', 'authors', 'keywords', 'ftpFile']
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless mime_types.include?(params[:file][:type]) if params[:file]
        inv_type = investigation_type
        
        # no data or ftp data
        if params[:type] && !params[:file]
          bad_request_error "Parameter '#{params[:type]}' not supported." unless inv_types.include? params[:type]
          case params[:type]
          when "noData"
            bad_request_error "Expected type is '#{inv_type}'." unless params[:type] == inv_type
            bad_request_error "Parameter 'ftpFile' not expected for type '#{params[:type]}'." if params[:ftpFile]
            clean_params "noftp"
            prepare_upload
            params2rdf
          when "ftpData"
            bad_request_error "Expected type is '#{inv_type}'." unless params[:type] == inv_type
            clean_params "ftp"
            prepare_upload
            params2rdf
          end
        # unformated data
        elsif params[:type] && params[:file]
          bad_request_error "Parameter '#{params[:type]}' not supported." unless inv_types.include? params[:type]
          bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip)." unless mime_types[0] == params[:file][:type]
          bad_request_error "No file expected for type '#{params[:type]}'." unless params[:type] == "unformattedData"
          bad_request_error "File '#{params[:file][:filename]}' is to large. Please choose FTP investigation type and upload to your FTP directory first." unless (params[:file][:tempfile].size.to_i < 10485760)
          bad_request_error "Expected type is '#{inv_type}'." unless params[:type] == inv_type
          clean_params "noftp"
          prepare_upload
          params2rdf
        # isatab data
        elsif params[:file] && !params[:type]
          bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
          bad_request_error "Unable to edit unformatted investigation with ISA-TAB data." unless is_isatab? 
          prepare_upload
          extract_zip if params[:file][:type] == 'application/zip'
          kill_isa2rdf
          isa2rdf
        # set flags and policies
        elsif !params[:type] && !inv_type.blank? && (params[:summarySearchable]||params[:published]||params[:allowReadByGroup]||params[:allowReadByUser])
          # pass to set flags or policies
        # require type for non-isatab
        elsif !params[:type] && !inv_type.blank?
          bad_request_error "Expected type is '#{inv_type}'."
        # incomplete request
        elsif !params[:file] && !params[:type] && !params[:summarySearchable] && !params[:published] && !params[:allowReadByGroup] && !params[:allowReadByUser]
          bad_request_error "No file uploaded or any valid parameter given."
        end
        
        set_flag(RDF::TB.isPublished, (params[:published].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:published])
        set_flag(RDF::TB.isSummarySearchable, (params[:summarySearchable].to_s == "true" ? true : false), "boolean") if params[:file] || (!params[:file] && params[:summarySearchable])
        set_modified
        create_policy "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        curi = clean_uri(uri)
        if qfilter("isPublished", curi) =~ /#{curi}/ && qfilter("isSummarySearchable", curi) =~ /#{curi}/
          $logger.debug "index investigation"
          set_index true
        else
          set_index false
        end
        investigation_uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # @method delete_id
    # @overload delete "/investigation/:id"
    # Delete an investigation
    # @param [Hash] header * subjectid [String] authorization token
    # @return [String] status message and HTTP code
    # @see http://api.toxbank.net/index.php/Investigation#Delete_an_investigation API: Delete an investigation
    delete '/investigation/:id' do
      kill_isa2rdf
      set_index false
      FileUtils.remove_entry dir
      `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{OpenTox::Authorization.get_user}"`
      FourStore.delete investigation_uri
      delete_investigation_policy
      response['Content-Type'] = 'text/plain'
      "Investigation #{params[:id]} deleted"
    end

    # @!endgroup

    # Delete an individual study, assay or data file
    ['/investigation/:id/isatab/:filename', '/investigation/:id/files/:filename'].each  do |path|
      delete path do
        task = OpenTox::Task.run("Deleting #{params[:filename]} from investigation #{params[:id]}.",@uri) do
          if path.include?("isatab") 
            prepare_upload
            File.delete File.join(tmp,params[:filename])
            isa2rdf
          else
          #TODO delete file triple from metadata.nt and overwrite in backend
            File.delete File.join(dir,params[:filename])
          end
        end
        response['Content-Type'] = 'text/uri-list'
        halt 202,task.uri+"\n"
      end
    end
  end
end
