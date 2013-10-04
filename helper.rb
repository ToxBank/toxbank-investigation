module OpenTox
  # full API description for ToxBank investigation service see:
 # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    module Helpers
      # @return [String] full investigation URI: investigation service uri + investigation[:id]
      def investigation_uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      # @return [String] uri-list of files in investigation[:id] folder
      def uri_list
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f| to(f.sub(/\.\//,'')) }
        uris.collect!{|u| u.sub(/(\/#{params[:id]}\/)/,'\1isatab/')} if params[:id]
        uris.delete_if{|u| u.match(/_policies$/)}
        uris.compact.sort.join("\n") + "\n"
      end

      # @return [String] absolute investigation dir path
      def dir
        File.join File.dirname(File.expand_path __FILE__), "investigation", params[:id].to_s
      end

      # @return [String] absolute investigation dir/tmp path
      def tmp
        File.join dir,"tmp"
      end

      # @return [String] file name with absolute path
      def file
        File.join dir, params[:filename]
      end

      # @return [String] N-Triples file name
      def nt
        "#{params[:id]}.nt"
      end

      # @return [Integer] timestamp of a time string
      def get_timestamp timestring
        Time.parse(timestring).to_i
      end

      # deletes all policies of an investigation
      def delete_investigation_policy
        if RestClientWrapper.subjectid and !File.exists?(dir) and investigation_uri
          res = OpenTox::Authorization.delete_policies_from_uri(investigation_uri)
        end
      end

      # copy investigation files in tmp subfolder
      def prepare_upload
        locked_error "Processing investigation #{params[:id]}. Please try again later." if File.exists? tmp
        bad_request_error "Please submit data as multipart/form-data" unless request.form_data?
        # move existing ISA-TAB files to tmp
        FileUtils.mkdir_p tmp
        FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
        FileUtils.cp params[:file][:tempfile], File.join(tmp, params[:file][:filename])
      end

      # extract zip upload to tmp subdirectory of investigation
      def extract_zip
        `unzip -o #{File.join(tmp,params[:file][:filename])} -d #{tmp}`
        Dir["#{tmp}/*"].collect{|d| d if File.directory?(d)}.compact.each  do |d|
          `mv #{d}/* #{tmp}`
          `rmdir #{d}`
        end
        replace_pi
      end

      # process Excel file
      def extract_xls
        # use Excelx.new instead of Excel.new if your file is a .xlsx
        # @todo delete dir if task catches error, e.g. password locked, pass error to block
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

      # ISA-TAB to RDF conversion.
      # Preprocess and parse isa-tab files with java isa2rdf
      # @see https://github.com/ToxBank/isa2rdf
      def isa2rdf
        # @note isa2rdf returns correct exit code but error in task
        # @todo delete dir if task catches error, pass error to block
        `cd #{File.dirname(__FILE__)}/java && java -jar -Xmx2048m isa2rdf-cli-0.0.7.jar -d #{tmp} -o #{File.join tmp,nt} -t #{$user_service[:uri]} `#&> #{File.join tmp,'log'}`
        `sed -i 's;http://onto.toxbank.net/isa/tmp/;#{investigation_uri}/;g' #{File.join tmp,nt}`
        investigation_id = `grep "#{investigation_uri}/I[0-9]" #{File.join tmp,nt}|cut -f1 -d ' '`.strip
        `sed -i 's;#{investigation_id.split.last};<#{investigation_uri}>;g' #{File.join tmp,nt}`
        `echo '\n<#{investigation_uri}> <#{RDF::DC.modified}> "#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}" .' >> #{File.join tmp,nt}`
        `echo "\n<#{investigation_uri}> <#{RDF.type}> <#{RDF::OT.Investigation}> ." >>  #{File.join tmp,nt}`
        FileUtils.rm Dir[File.join(tmp,"*.zip")]
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        `zip -j #{File.join(dir, "investigation_#{params[:id]}.zip")} #{dir}/*.txt`
        OpenTox::Backend::FourStore.put investigation_uri, File.read(File.join(dir,nt)), "application/x-turtle"
        FileUtils.remove_entry tmp
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files --others --exclude-standard --directory #{params[:id]}`
        `cd #{File.dirname(__FILE__)}/investigation && git add #{newfiles}`
        request.env['REQUEST_METHOD'] == "POST" ? action = "created" : action = "modified"
        `cd #{File.dirname(__FILE__)}/investigation && git commit -am "investigation #{params[:id]} #{action} by #{OpenTox::Authorization.get_user}"`
        investigation_uri
      end

      # creates XML policy file for user or group
      # @param [String]ldaptype is 'user' or 'group'
      # @param [String]uristring URI of user/group in user service
      # @see http://api.toxbank.net/index.php/User
      def create_policy ldaptype, uristring
        filename = File.join(dir, "#{ldaptype}_policies")
        policyfile = File.open(filename,"w")
        uriarray = uristring if uristring.class == Array
        uriarray = uristring.gsub(/[\[\]\"]/ , "").split(",") if uristring.class == String
        if uriarray.size > 0
          uriarray.each do |u|
            tbaccount = OpenTox::TBAccount.new(u)
            policyfile.puts tbaccount.get_policy(investigation_uri)
          end
          policyfile.close
          policytext = File.read filename
          replace = policytext.gsub!("</Policies>\n<!DOCTYPE Policies PUBLIC \"-//Sun Java System Access Manager7.1 2006Q3 Admin CLI DTD//EN\" \"jar://com/sun/identity/policy/policyAdmin.dtd\">\n<Policies>\n", "")
          File.open(filename, "w") { |file| file.puts replace } if replace
          Authorization.reset_policies investigation_uri, ldaptype
          ret = Authorization.create_policy(File.read(policyfile))
          File.delete policyfile if ret
        else
          Authorization.reset_policies investigation_uri, ldaptype
        end
      end

      # switch boolean flags in triple store
      # @param [String]flag e.G.: isPublished, isSummarySearchable
      # @param [Boolean]value
      # @param [String]type boolean
      def set_flag flag, value, type = ""
        flagtype = type == "boolean" ? "^^<#{RDF::XSD.boolean}>" : ""
        OpenTox::Backend::FourStore.update "DELETE DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{flag}> \"#{!value}\"#{flagtype}}}"
        OpenTox::Backend::FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{flag}> \"#{value}\"#{flagtype}}}"
      end

      # add or delete investigation_uri from search index at UI
      # @param inout [Boolean] true=add, false=delete
      def set_index inout=false
        OpenTox::RestClientWrapper.method(inout ? "put" : "delete").call "#{$search_service[:uri]}/search/index/investigation?resourceUri=#{CGI.escape(investigation_uri)}",{},{:subjectid => OpenTox::RestClientWrapper.subjectid}
      end

      # return uri if related flag is set to "true".
      # @return [String] URI
      def qfilter(flag, uri)
        qfilter = OpenTox::Backend::FourStore.query "SELECT ?s FROM <#{uri}> WHERE {?s <#{RDF::TB}#{flag}> ?o FILTER regex(?o, 'true', 'i')}", "application/sparql-results+xml"
        $logger.debug "\ncheck flags: #{qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '').strip}\n"
        qfilter.split("\n")[7].gsub(/<binding name="s"><uri>|\/<\/uri><\/binding>/, '').strip
      end

      # manage Get requests with policies and flags.
      def get_permission
        return false if request.env['REQUEST_METHOD'] != "GET"
        uri = to(request.env['REQUEST_URI'])
        curi = clean_uri(uri)
        return true if uri == $investigation[:uri]
        return true if OpenTox::Authorization.get_user == "protocol_service"
        return true if OpenTox::Authorization.uri_owner?(curi)
        if (request.env['REQUEST_URI'] =~ /metadata/ ) || (request.env['REQUEST_URI'] =~ /protocol/ )
          return true if qfilter("isSummarySearchable", curi) =~ /#{curi}/
        end
        return true if OpenTox::Authorization.authorized?(curi, "GET") && qfilter("isPublished", curi) =~ /#{curi}/
        return false
      end

      # generate URI list.
      def qlist mime_type
        list = OpenTox::Backend::FourStore.list mime_type
        service_uri = to("/investigation")
        list.split.keep_if{|v| v =~ /#{service_uri}/}.join("\n")# show all, ignore flags
      end

      # replaces pi uri with owner uri (use uri prefix) in i_*vestigation.txt file.
      def replace_pi
        begin
          user = OpenTox::Authorization.get_user
          #accounturi = OpenTox::RestClientWrapper.get("#{$user_service[:uri]}/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
          accounturi = `curl -Lk -X GET -H "Accept:text/uri-list" -H "subjectid:#{RestClientWrapper.subjectid}" #{$user_service[:uri]}/user?username=#{user}`.chomp.sub("\n","")
          account = OpenTox::TBAccount.new(accounturi)
          investigation_file = Dir["#{tmp}/i_*vestigation.txt"]
          investigation_file.each do |inv_file|
            text = File.read(inv_file, :encoding => "BINARY")
            #replace = text.gsub!(/TBU:U\d+/, account.ns_uri)
            replace = text.gsub!(/Comment \[Principal Investigator URI\]\t"TBU:U\d+"/ , "Comment \[Owner URI\]\t\"#{account.ns_uri}\"")
            replace = text.gsub!(/Comment \[Owner URI\]\t"TBU:U\d+"/ , "Comment \[Owner URI\]\t\"#{account.ns_uri}\"")
            File.open(inv_file, "wb") { |file| file.puts replace } if replace
          end
        rescue
          $logger.error "can not replace Principal Investigator to user: #{user} with subjectid: #{RestClientWrapper.subjectid}"
        end
      end
    end
  end
end
