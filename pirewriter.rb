def replace_pi subjectid
  begin
    user = OpenTox::Authorization.get_user(subjectid)
    accounturi = OpenTox::RestClientWrapper.get("http://toxbanktest1.opentox.org:8080/toxbank/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
    account = OpenTox::TBAccount.new(accounturi, subjectid)
    investigation_file = Dir["#{tmp}/i_*vestigation.txt"]
    investigation_file.each do |inv_file|
      text = File.read(inv_file, :encoding => "BINARY")
      replace = text.gsub!(/TBU:U\d+/, account.ns_uri)
      File.open(inv_file, "wb") { |file| file.puts replace } if replace
    end
  rescue
    $logger.error "can not replace Principal Investigator to user: #{user} with subjectid: #{subjectid}"
  end
end
