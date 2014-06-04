module OpenTox
  # full API description for ToxBank investigation service see:
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    module Helpers
      
      def validate_params_uri(param, value)
        keys = ["owningOrg", "owningPro", "authors", "keywords"]
        if keys.include?(param.to_s)
          (value.uri? && value =~ /toxbank/) ? (return true) : (return false)
        end
      end
      
      def get_pi
        user = OpenTox::Authorization.get_user
        accounturi = `curl -Lk -X GET -H "Accept:text/uri-list" -H "subjectid:#{RestClientWrapper.subjectid}" #{$user_service[:uri]}/user?username=#{user}`.chomp.sub("\n","")
        accounturi
      end
      
      # Parameters to RDF conversion.
      def params2rdf
        #$logger.debug params.inspect
        FileUtils.cp(File.join(File.dirname(File.expand_path __FILE__), "template", "metadata.nt"), File.join(tmp,nt))
        metadata = File.read(File.join(tmp,nt)) % {:investigation_uri => investigation_uri,
          :type => params[:type],
          :title => params[:title].strip,
          :abstract => params[:abstract].strip.gsub(/\r\n/,"\\n"), # catch ^M character
          :organisation => params[:owningOrg],
          :pi => get_pi
        }
        if request.env['REQUEST_METHOD'] =~ /POST/
          metadata << "<#{investigation_uri}> <http://purl.org/dc/terms/issued> \"#{Time.new.strftime("%d %b %Y %H:%M:%S %Z")}\" .\n"
        else
          issued = ""
          IO.readlines(File.join(dir,nt)).each{|l| issued << l if l =~ /issued/}
          metadata << issued
        end
        # if several params has different values
        owningPro = params[:owningPro].split(",")
        owningPro.each do |project|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasProject> <#{project.strip}> .\n"
        end
        authors = params[:authors].split(",")
        authors.each do |author|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasAuthor> <#{author.strip}> .\n"
        end
        keywords = params[:keywords].split(",")
        keywords.each do |keyword|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasKeyword> <#{keyword.strip}> .\n"
        end
        if params[:file]
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasDownload> <#{investigation_uri}/files/#{params[:file][:filename].gsub(/\s/, "%20")}> .\n"
        end
        if params[:ftpFile]
          ftpData = params[:ftpFile].split(",")
          ftpData.each do |ftp|
            metadata << "<#{investigation_uri}> <#{RDF::TB}hasDownload> <#{investigation_uri}/files/#{ftp.strip.gsub(/\s/, "%20")}> .\n"
          end
          link_ftpfiles_by_params
        else
          remove_symlinks
        end

        #$logger.debug metadata
        File.open(File.join(tmp,nt), 'w'){|f| f.write(metadata)}
        FileUtils.cp Dir[File.join(tmp,"*")], dir
        FileUtils.remove_entry tmp
        OpenTox::Backend::FourStore.put investigation_uri, File.read(File.join(dir,nt)), "application/x-turtle"
        investigation_uri
      end

      #link ftp files by params
      def link_ftpfiles_by_params
        ftpfiles = get_ftpfiles
        paramfiles = params[:ftpFile].gsub(/,\s/, ",").split(",")
        # remove existing from dir
        remove_symlinks
        paramfiles.each do |file|
          bad_request_error "'#{file}' is missing. Please upload to your ftp directory first." if !ftpfiles.include?(file)
          `ln -s "/home/ftpusers/#{Authorization.get_user}/#{file}" "#{dir}/#{file.gsub("/","_")}"` unless File.exists?("#{dir}/#{file}") 
          ftpfilesave = "<#{investigation_uri}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file.gsub("/","_")}> ."
          File.open(File.join(dir, "ftpfiles.nt"), 'a') {|f| f.write("#{ftpfilesave}\n") }
          # update backend
          OpenTox::Backend::FourStore.update "WITH <#{investigation_uri}>
          DELETE { <#{investigation_uri}> <#{RDF::ISA.hasDownload}> ?o} WHERE {<#{investigation_uri}> <#{RDF::ISA.hasDownload}> ?o};
          INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file.gsub("/","_")}>}}"
        end
      end

    end
  end
end
