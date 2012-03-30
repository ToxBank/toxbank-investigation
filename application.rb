require "opentox-server"
require File.join(ENV["HOME"],".opentox","config","toxbank-investigation","production.rb")

module OpenTox
  class Application < Service

    helpers do

      def uri
        params[:id] ? url_for("/#{params[:id]}", :full) : "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
      end

      def uri_list 
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f|  url_for(f.sub(/\.\/investigation/,''), :full) }
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
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

      def next_id
        id = Dir["./investigation/*"].collect{|f| File.basename(f).to_i}.sort.last
        id ? id + 1 : 0
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
          `cd #{File.dirname(__FILE__)}/java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d #{tmp} -o #{File.join tmp,n3} &> #{File.join tmp,'log'}`
        rescue
          log = File.read File.join(tmp,"log")
          FileUtils.remove_entry dir
          bad_request_error "ISA-TAB validation failed:\n#{log}", uri
        end
        # rewrite default prefix
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{uri}/;' #{File.join tmp,n3}`
        # add owl:sameAs to identify investigation later
        investigation_id = `grep ":I[0-9]" #{File.join tmp,n3}|cut -f1 -d ' '`.strip
        `echo "\n: owl:sameAs #{investigation_id} ." >>  #{File.join tmp,n3}`
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
        length = File.size(File.join dir,n3)
        file = File.join(dir,n3)
        `curl -0 -k -u #{$four_store[:user]}:#{$four_store[:password]} -T #{file} -H 'Content_Length => #{length}' '#{$four_store[:uri]}/data/?graph=#{$four_store[:uri]}/data/#{$four_store[:user]}/investigation#{n3}'`
        FileUtils.remove_entry tmp  # unlocks tmp
        OpenTox::Authorization.check_policy(uri, @subjectid)
        uri
      end

      def query sparql
        if @accept.match(/turtle/) and sparql.match(/CONSTRUCT/)
          response['Content-type'] = @accept
        elsif sparql.match(/CONSTRUCT/)
          response['Content-type'] = 'application/rdf+xml'
        else
          response['Content-type'] = "application/sparql-results+xml"
        end
        `curl -H 'Accept:#{@accept}' -k -u #{$four_store[:user]}:#{$four_store[:password]} -d 'query=#{sparql}' '#{$four_store[:uri]}/sparql/'`
      end
      
    end

    before do
      not_found_error "Directory #{dir} does not exist."  unless File.exist? dir
      @accept = request.env['HTTP_ACCEPT']
      response['Content-Type'] = @accept
      # TODO: A+A
    end

    # Query all investigations or get a list of all investigations
    # Requests with a query parameter will perform a SPARQL query on all investigations
    # @return [application/sparql-results+json] Query result
    # @return [text/uri-list] List of investigations
    get '/?' do
      if params[:query] # pass SPARQL query to 4store
        query params[:query]
      else
        # Requests without a query parameter return a list of all investigations
        case @accept
        when 'text/uri-list'
          uri_list
        else
          response['Content-Type'] = 'application/rdf+xml'
          response['Content-Type'] = @accept if @accept == 'text/turtle'
          query "
            PREFIX isa: <http://onto.toxbank.net/isa/>
            CONSTRUCT { ?s ?p ?o . }
            WHERE {
              ?s a isa:Investigation ;
                ?p ?o .
              }
          "
        end
      end
    end

    # Create a new investigation from ISA-TAB files
    # @param [Header] Content-type: multipart/form-data
    # @param file Zipped investigation files in ISA-TAB format
    # @return [text/uri-list] Investigation URI 
    post '/?' do
      params[:id] = next_id
      mime_types = ['application/zip','text/tab-separated-values', "application/vnd.ms-excel"]
      bad_request_error "No file uploaded." unless params[:file]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      task = OpenTox::Task.create($task[:uri], :description => "#{params[:file][:filename]}: Uploding, validating and converting to RDF") do
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
    get '/:id' do
      not_found_error "Investigation #{uri} does not exist."  unless File.exist? dir # not called in before filter???
      case @accept
      when "text/tab-separated-values"
        send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
      when "text/uri-list"
        uri_list
      when "application/zip"
        send_file File.join dir, "investigation_#{params[:id]}.zip"
      when "application/rdf+xml"
        query "CONSTRUCT { ?s ?p ?o } FROM <#{$four_store[:uri]}/data/#{$four_store[:user]}/investigation#{n3}> WHERE {?s ?p ?o } LIMIT 15000"
      else
        #$logger.debug request.to_yaml
        #bad_request_error "Accept header #{@accept} not supported for #{uri}"
        $logger.warn "Accept header #{@accept} not supported for #{uri}" # do not halt: strange requests from test, TODO: identify and fix
      end
    end

    # Get investigation metadata in RDF
    get '/:id/metadata' do
      not_found_error "Investigation #{uri} does not exist."  unless File.exist? dir # not called in before filter???
      query "
        PREFIX : <#{uri}/>
        PREFIX owl: <http://www.w3.org/2002/07/owl#>
        CONSTRUCT { ?s ?p ?o.  }
        WHERE {
          : owl:sameAs ?s .
          ?s ?p ?o .
        }
      "
    end

    # Get a study, assay, data representation
    # @param [Header] one of text/tab-separated-values, application/sparql-results+json
    # @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
    get '/:id/isatab/:filename'  do
      not_found_error "File #{File.join uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
      # TODO: returns text/plain content type for tab separated files
      send_file file, :type => File.new(file).mime_type
    end

    # Get RDF for an investigation resource
    get '/:id/:resource' do
      query "
        PREFIX : <#{uri}/>
        PREFIX owl: <http://www.w3.org/2002/07/owl#>
        CONSTRUCT { :#{params[:resource]} ?p ?o.  }
        WHERE {
          :#{params[:resource]} ?p ?o .
        }
      "
    end

    # Add studies, assays or data to an investigation
    # @param [Header] Content-type: multipart/form-data
    # @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
    post '/:id' do
      mime_types = ['application/zip','text/tab-separated-values', "application/vnd.ms-excel"]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      task = OpenTox::Task.create($task[:uri], :description => "#{params[:file][:filename]}: Uploding, validationg and converting to RDF") do
        prepare_upload
        isa2rdf
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Delete an investigation
    delete '/:id' do
      FileUtils.remove_entry dir
      # git commit
      `cd #{File.dirname(__FILE__)}/investigation; git commit -am "#{dir} deleted by #{request.ip}"`
      # updata RDF
      `curl -i -k -u #{$four_store[:user]}:#{$four_store[:password]} -X DELETE '#{$four_store[:uri]}/data/#{$four_store[:user]}/investigation#{n3}'`
      response['Content-Type'] = 'text/plain'
      "Investigation #{params[:id]} deleted"
    end

    # Delete an individual study, assay or data file
    delete '/:id/:filename'  do
      task = OpenTox::Task.create($task[:uri], :description => "Deleting #{params[:file][:filename]} from investigation #{params[:id]}.") do
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
