require "opentox-server"
require "#{File.dirname(__FILE__)}/tbaccount.rb"

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
        RestClient.put File.join(four_store_uri,"data",investigation_uri), File.read(File.join(dir,n3)), :content_type => "application/x-turtle" # content-type not very consistent in 4store
        FileUtils.remove_entry tmp  # unlocks tmp
        investigation_uri
      end

      def create_policy_file ldaptype, uristring
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
        rescue
          $logger.warn "create policies error for Investigation URI: #{investigation_uri} for user/group uris: #{uristring}"
        end
      end

      def send_policies
        ["user","group"].each do |policytype|
          policyfile = File.join dir, "#{policytype}_policies"
          if File.exists?(policyfile)
            ret = Authorization.create_policy(File.read(policyfile), @subjectid)
            File.delete policyfile if ret
          end
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
      mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
      bad_request_error "No file uploaded." unless params[:file]
      bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
      bad_request_error "The file #{params[:file][:filename]} contains no investigation file." unless `unzip -Z -1 #{File.join(params[:file][:tempfile])}`.include? "i_Investigation.txt"
      task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file][:filename]}: Uploading, validating and converting to RDF") do
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
        OpenTox::Authorization.create_pi_policy(investigation_uri, @subjectid)
        create_policy_file "user", params[:allowReadByUser] if params[:allowReadByUser]
        create_policy_file "group", params[:allowReadByGroup] if params[:allowReadByGroup]
        investigation_uri
      end
      response['Content-Type'] = 'text/uri-list'
      halt 202,task.uri+"\n"
    end

    # Get an investigation representation
    # @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
    # @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
    get '/investigation/:id' do
      not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      case @accept
      when "text/tab-separated-values"
        send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
      when "text/uri-list"
        uri_list
      when "application/zip"
        send_file File.join dir, "investigation_#{params[:id]}.zip"
      else
        FourStore.query "CONSTRUCT { ?s ?p ?o } FROM <#{investigation_uri}> WHERE {?s ?p ?o } LIMIT 15000", @accept
      end
    end

    # Get investigation metadata in RDF
    get '/investigation/:id/metadata' do
      not_found_error "Investigation #{investigation_uri} does not exist."  unless File.exist? dir # not called in before filter???
      FourStore.query "CONSTRUCT { ?s ?p ?o.  } FROM <#{investigation_uri}> WHERE { ?s <#{RDF.type}> <http://onto.toxbank.net/isa/Investigation>. ?s ?p ?o .  } ", @accept
    end

    # Get a study, assay, data representation
    # @param [Header] one of text/tab-separated-values, application/sparql-results+json
    # @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
    get '/investigation/:id/isatab/:filename'  do
      not_found_error "File #{File.join investigation_uri,"isatab",params[:filename]} does not exist."  unless File.exist? file
      # TODO: returns text/plain content type for tab separated files
      send_file file, :type => File.new(file).mime_type
    end

    # Get RDF for an investigation resource
    get '/investigation/:id/:resource' do
      FourStore.query " CONSTRUCT {  <#{File.join(investigation_uri,params[:resource])}> ?p ?o.  } FROM <#{investigation_uri}> WHERE { <#{File.join(investigation_uri,params[:resource])}> ?p ?o .  } ", @accept
    end

    # Add studies, assays or data to an investigation
    # @param [Header] Content-type: multipart/form-data
    # @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
    put '/investigation/:id' do
      if params[:file]
        mime_types = ['application/zip','text/tab-separated-values', 'application/vnd.ms-excel']
        bad_request_error "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip), Excel file (application/vnd.ms-excel) or as tab separated text (text/tab-separated-values)" unless mime_types.include? params[:file][:type]
        task = OpenTox::Task.create($task[:uri], @subjectid, RDF::DC.description => "#{params[:file][:filename]}: Uploding, validationg and converting to RDF") do
          prepare_upload
          case params[:file][:type]
          when 'application/zip'
            extract_zip
          end
          isa2rdf
        end
      end
      create_policy_file "user", params[:allowReadByUser] if params[:allowReadByUser]
      create_policy_file "group", params[:allowReadByGroup] if params[:allowReadByGroup]
      send_policies if params[:published] && params[:published] == "true"
      response['Content-Type'] = 'text/uri-list'
      if params[:file]
        halt 202,task.uri+"\n"
      else
        investigation_uri+"\n"
      end
    end

    # Delete an investigation
    delete '/investigation/:id' do
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
