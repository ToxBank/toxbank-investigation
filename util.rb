# replaces pi uri with owner uri (use uri prefix)  
def replace_pi subjectid
  begin
    user = OpenTox::Authorization.get_user(subjectid)
    #accounturi = OpenTox::RestClientWrapper.get("#{$user_service[:uri]}/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
    accounturi = `curl -Lk -X GET -H "Accept:text/uri-list" -H "subjectid:#{subjectid}" #{$user_service[:uri]}/user?username=#{user}`.chomp.sub("\n","")
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

# workaround for SSLv3 requests with cert
# @see http://stackoverflow.com/questions/6821051/ruby-ssl-error-sslv3-alert-unexpected-message
# @see http://stackoverflow.com/questions/2507902/how-to-validate-ssl-certificate-chain-in-ruby-with-net-http
def request_ssl3 uri, type="get", subjectid=nil
  url = URI.parse(uri)
  fullurl = "#{url.path}?#{url.query}"
  case type
  when "get"
    req = Net::HTTP::Get.new(fullurl)
  when "delete"
    req = Net::HTTP::Delete.new(fullurl)
  when "put"
    req = Net::HTTP::Put.new(fullurl)
  end
  req['subjectid'] = subjectid if subjectid
  sock = Net::HTTP.new(url.host, 443)
  sock.use_ssl = true
  sock.ssl_version="SSLv3"
  sock.verify_mode = OpenSSL::SSL::VERIFY_NONE
  sock.start do |http|
    @response = http.request(req)
  end
  return @response
end

# For an explanation, see post at http://xampl.com/so/2009/12/16/rubyrack-and-multiple-value-request-param-pain-�~@~T-part-one/
module Rack
  module Utils

    def normalize_params(params, name, v = nil)
      name =~ %r(\A[\[\]]*([^\[\]]+)\]*)
      k = $1 || ''
      after = $' || ''

      return if k.empty?

      if after == ""
        # The original simply did: params[k] = v
        case params[k]
          when Array
            params[k] << v
          when String
            params[k] = [ params[k], v ]
          else
            params[k] = v
        end
      elsif after == "[]"
        params[k] ||= []
        raise TypeError, "expected Array (got #{params[k].class.name}) for param `#{k}'" unless params[k].is_a?(Array)
        params[k] << v
      elsif after =~ %r(^\[\]\[([^\[\]]+)\]$) || after =~ %r(^\[\](.+)$)
        child_key = $1
        params[k] ||= []
        raise TypeError, "expected Array (got #{params[k].class.name}) for param `#{k}'" unless params[k].is_a?(Array)
        if params[k].last.is_a?(Hash) && !params[k].last.key?(child_key)
          normalize_params(params[k].last, child_key, v)
        else
          params[k] << normalize_params({}, child_key, v)
        end
      else
        params[k] ||= {}
        raise TypeError, "expected Hash (got #{params[k].class.name}) for param `#{k}'" unless params[k].is_a?(Hash)
        params[k] = normalize_params(params[k], after, v)
      end

      return params
    end

    module_function :normalize_params

  end
end
