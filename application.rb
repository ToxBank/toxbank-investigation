require 'roo'
require 'opentox-server'
require "#{File.dirname(__FILE__)}/tbaccount.rb"
require "#{File.dirname(__FILE__)}/util.rb"
require "#{File.dirname(__FILE__)}/helpers.rb"

module OpenTox
  # full API description for ToxBank investigation service see:  
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    helpers do
      include Helpers
      # overwrite opentox-server method for toxbank use
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
    
    # list URIs of all investigations or investigations of a user
    # @return [String] text/uri-list, application/rdf+xml, application/json List of investigations
    get '/investigation/?' do
      bad_request_error "Mime type #{@accept} not supported here. Please request data as text/uri-list, application/json or application/rdf+xml." unless (@accept.to_s == "text/uri-list") || (@accept.to_s == "application/rdf+xml") || (@accept.to_s == "application/json")
      if (@accept == "text/uri-list" || @accept == "application/rdf+xml") && !request.env['HTTP_USER']
        qlist @accept
      elsif (@accept == "application/rdf+xml" && request.env['HTTP_USER'])
        FourStore.query "CONSTRUCT {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation> }
        WHERE {?investigation <#{RDF.type}> <#{RDF::ISA}Investigation>. ?investigation <#{RDF::TB}hasOwner> <#{request.env['HTTP_USER']}>}", @accept
      elsif (@accept == "application/json" && request.env['HTTP_USER'])
        response = FourStore.query "SELECT ?uri ?updated WHERE {?uri <#{RDF::TB}hasOwner> <#{request.env["HTTP_USER"]}>; <#{RDF::DC.modified}> ?updated}", @accept
        response.gsub(/(\d{2}\s[a-zA-Z]{3}\s\d{4}\s\d{2}\:\d{2}\:\d{2}\s[A-Z]{3})/){|t| get_timestamp t}
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
      # @todo return text/plain content type for tab separated files
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
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "Deleting #{params[:filename]} from investigation #{params[:id]}.") do
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
