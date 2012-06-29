def replace_pi subjectid
  begin
    $logger.debug "pirewriter 1"
    user = OpenTox::Authorization.get_user(subjectid)
    $logger.debug "pirewriter 2 user: #{user}"
    accounturi = OpenTox::RestClientWrapper.get("http://toxbanktest1.opentox.org:8080/toxbank/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
    $logger.debug "pirewriter 3 acccounturi: #{accounturi}"
    account = OpenTox::TBAccount.new(accounturi, subjectid)
    $logger.debug "pirewriter 4"
    investigation_file = Dir["#{tmp}/i_*vestigation.txt"]
    $logger.debug "pirewriter 5"
    investigation_file.each do |inv_file|
      $logger.debug "pirewriter 6 inv_file: #{inv_file}"
      text = File.read(inv_file, :encoding => "BINARY")
      $logger.debug "pirewriter 7"
      replace = text.gsub!(/TBU:U\d+/, account.ns_uri)
      $logger.debug "pirewriter 8"
      File.open(inv_file, "wb") { |file| file.puts replace } if replace
    end
  rescue
    $logger.error "can not replace Principal Investigator to user: #{user} with subjectid: #{subjectid}"
  end
end
