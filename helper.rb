module OpenTox
  # full API description for ToxBank investigation service see:
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    module Helpers
      # @!group File and Directory Helpers
      # @return [String] full investigation URI: investigation service uri + investigation[:id]
      def investigation_uri
        to("/investigation/#{params[:id]}") # new in Sinatra, replaces url_for
      end

      # @return [String] uri-list of files in investigation[:id] folder
      def uri_list
        params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
        uris = Dir[d].collect{|f| to(f.sub(/\.\//,'')) }
        uris.collect!{|u| u.sub(/(\/#{params[:id]}\/)/,'\1isatab/')} if params[:id]
        uris.collect!{|u| u.sub(/(\/isatab\/)/,'/files/')} if params[:id] && File.read(File.join(dir,nt)).match("hasInvType")
        uris.delete_if{|u| u.match(/_policies$/)}
        uris.delete_if{|u| u.match(/log$|modified\.nt$|isPublished\.nt$|isSummarySearchable\.nt$|ftpfiles\.nt$/)}
        uris.map!{ |u| u.gsub(" ", "%20") }
        uris.map!{ |u| File.symlink?("#{dir}/#{File.basename(u)}") ? u.gsub("/isatab/", "/files/") : u}
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
      
      # @!endgroup
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
      # @param [String]flag e.G.: RDF::TB.isPublished, RDF::TB.isSummarySearchable
      # @param [Boolean]value
      # @param [String]type boolean
      def set_flag flag, value, type = ""
        flagtype = type == "boolean" ? "^^<#{RDF::XSD.boolean}>" : ""
        OpenTox::Backend::FourStore.update "DELETE DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{flag}> \"#{!value}\"#{flagtype}}}"
        OpenTox::Backend::FourStore.update "INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{flag}> \"#{value}\"#{flagtype}}}"
        # save flag to file in case of restore or transport backend
        flagsave = "<#{investigation_uri}> <#{flag}> \"#{value}\"#{flagtype} ."
        File.open(File.join(dir, "#{flag.to_s.split("/").last}.nt"), 'w') {|f| f.write(flagsave) }
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files -z --others --exclude-standard --directory #{params[:id]}`
        request.env['REQUEST_METHOD'] == "POST" ? action = "created" : action = "modified"
        if newfiles != ""
          newfiles.split("\0").each{|newfile|`cd #{File.dirname(__FILE__)}/investigation && git add "#{newfile}"`}
          `cd #{File.dirname(__FILE__)}/investigation && git commit --allow-empty -am "#{newfiles.gsub("\0"," ::: ")}  #{action} by #{OpenTox::Authorization.get_user}"`
        else
          `cd #{File.dirname(__FILE__)}/investigation && git add "#{params[:id]}/#{flag.to_s.split("/").last}.nt" && git commit --allow-empty -am "#{params[:id]}/#{flag.to_s.split("/").last}.nt  #{action} by #{OpenTox::Authorization.get_user}"` if `cd #{File.dirname(__FILE__)}/investigation && git status -s| cut -c 4-` != ""
        end
      end

      # delete all RDF::DC.modified triples and insert new one with current date-time
      def set_modified
        OpenTox::Backend::FourStore.update "WITH <#{investigation_uri}>
        DELETE { <#{investigation_uri}> <#{RDF::DC.modified}> ?o} WHERE {<#{investigation_uri}> <#{RDF::DC.modified}> ?o};
        INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{RDF::DC.modified}> \"#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}\"}}"
        # save last modified to file in case of restore or transport backend
        modsave = "<#{investigation_uri}> <#{RDF::DC.modified}> \"#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}\" ." 
        File.open(File.join(dir, "modified.nt"), 'w') {|f| f.write(modsave) }
        newfiles = `cd #{File.dirname(__FILE__)}/investigation; git ls-files -z --others --exclude-standard --directory #{params[:id]}`
        request.env['REQUEST_METHOD'] == "POST" ? action = "created" : action = "modified"
        if newfiles != ""
          newfiles.split("\0").each{|newfile| `cd #{File.dirname(__FILE__)}/investigation && git add "#{newfile}"`}
          `cd #{File.dirname(__FILE__)}/investigation && git commit --allow-empty -am "#{newfiles.gsub("\0"," ::: ")}  #{action} by #{OpenTox::Authorization.get_user}"`
        else
          `cd #{File.dirname(__FILE__)}/investigation && git commit --allow-empty -am "#{params[:id]}/modified.nt  #{action} by #{OpenTox::Authorization.get_user}"` if `cd #{File.dirname(__FILE__)}/investigation && git status -s| cut -c 4-` != ""
        end
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
        if (request.env['REQUEST_URI'] =~ /investigation\/sparql/ || request.env['REQUEST_URI'] =~ /investigation\/ftpfiles/) # give permission to user groups defined in policies
          return true if OpenTox::Authorization.authorized?("#{$investigation[:uri]}", "GET")
        end
        if (request.env['REQUEST_URI'] =~ /metadata/ ) || (request.env['REQUEST_URI'] =~ /protocol/ )
          return true if qfilter("isSummarySearchable", curi) =~ /#{curi}/ && qfilter("isPublished", curi) =~ /#{curi}/
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

      # get SPARQL template hash of templatename => templatefile
      # @param type [String] template subdirectory
      def get_templates type=""
        templates = {}
        filenames = Dir[File.join File.dirname(File.expand_path __FILE__), "template/#{type}/*.sparql".gsub("//","/")]
        filenames.each{ |filename| templates[File.basename(filename, ".sparql")]=filename}
        return templates
      end

      # @!group Helpers to link FTP data
      # get an array of data files in an investigation
      def get_datafiles
        response = OpenTox::RestClientWrapper.get "#{investigation_uri}/sparql/files_with_datanodes_by_investigation", {}, {:accept => "application/json"}
        result = JSON.parse(response)
        files = result["results"]["bindings"].map{|n| "#{n["file"]["value"]}"}
        datanodes = result["results"]["bindings"].map{|n| "#{n["datanode"]["value"]}"}
        @datahash = {}
        result["results"]["bindings"].each{ |f| @datahash[File.basename(f["file"]["value"])].nil? ? @datahash[File.basename(f["file"]["value"])] = ["#{f["datanode"]["value"]}"] : @datahash[File.basename(f["file"]["value"])] << "#{f["datanode"]["value"]}"}
        return files.flatten
      end

      # get an array of files in ftp folder of a user
      def get_ftpfiles
        user = Authorization.get_user
        return [] if  !Dir.exists?("/home/ftpusers/#{user}") || user.nil?
        files = Dir.chdir("/home/ftpusers/#{user}") { Dir.glob("**/*").map{|path| File.expand_path(path) } }.reject{ |p| File.directory? p }
        Hash[files.collect { |f| [File.basename(f), f] }]
      end

      # remove existing symlinks
      def remove_symlinks
        Dir["#{tmp}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
        Dir["#{dir}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
        FileUtils.rm(File.join(dir, "ftpfiles.nt")) if File.exists? File.join(dir, "ftpfiles.nt")
      end

      # @!endgroup
    end
  end
end
