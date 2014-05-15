module OpenTox
  # full API description for ToxBank investigation service see:
  # @see http://api.toxbank.net/index.php/Investigation ToxBank API Investigation
  class Application < Service

    module Helpers
      
      def validate_params_uri(param, value)
        keys = ["owningOrg", "authors", "keywords"]
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
          :title => params[:title],
          :abstract => params[:abstract],
          :pi => get_pi,
        }
        # if several params has different values
        owningOrg = params[:owningOrg].gsub(/\s+/, "").split(",")
        owningOrg.each do |organisation|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasOrganisation> <#{organisation}> .\n"
        end
        authors = params[:authors].gsub(/\s+/, "").split(",")
        authors.each do |author|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasAuthor> <#{author}> .\n"
        end
        keywords = params[:keywords].gsub(/\s+/, "").split(",")
        keywords.each do |keyword|
          metadata << "<#{investigation_uri}> <#{RDF::TB}hasKeyword> <#{keyword}> .\n"
        end
        if params[:ftpFile]
          ftpData = params[:ftpFile].gsub(/\s+/, "").split(",")
          ftpData.each do |ftp|
            metadata << "<#{investigation_uri}> <#{RDF::TB}hasDownload> <#{investigation_uri}/files/#{ftp}> .\n"
          end
          link_ftpfiles_by_params
        else
          Dir["#{tmp}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
          Dir["#{dir}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
          FileUtils.rm(File.join(dir, "ftpfiles.nt")) if File.exists? File.join(dir, "ftpfiles.nt")
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
        paramfiles = params[:ftpFile].gsub(/\s+/, "").split(",")
        # remove existing from dir
        Dir["#{tmp}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
        Dir["#{dir}/*"].each{|file| FileUtils.rm(file) if File.symlink?("#{dir}/#{File.basename(file)}")}
        FileUtils.rm(File.join(dir, "ftpfiles.nt")) if File.exists? File.join(dir, "ftpfiles.nt")
        paramfiles.each do |file|
          bad_request_error "'#{file}' is missing. Please upload to your ftp directory first." if !ftpfiles.include?(file)
          `ln -s "#{ftpfiles[file]}" "#{dir}/#{file}"` unless File.exists?("#{dir}/#{file}")
          ftpfilesave = "<#{investigation_uri}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file}> ."
          File.open(File.join(dir, "ftpfiles.nt"), 'a') {|f| f.write("#{ftpfilesave}\n") }
          # update backend
          OpenTox::Backend::FourStore.update "WITH <#{investigation_uri}>
          DELETE { <#{investigation_uri}> <#{RDF::ISA.hasDownload}> ?o} WHERE {<#{investigation_uri}> <#{RDF::ISA.hasDownload}> ?o};
          INSERT DATA { GRAPH <#{investigation_uri}> {<#{investigation_uri}> <#{RDF::ISA.hasDownload}> <#{investigation_uri}/files/#{file}>}}"
        end
      end

    end
  end
end
