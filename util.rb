# replaces pi uri with owner uri (use uri prefix) in i_*vestigation.txt file
# @param [String] subjectid
def replace_pi subjectid
  begin
    user = OpenTox::Authorization.get_user(subjectid)
    #accounturi = OpenTox::RestClientWrapper.get("#{$user_service[:uri]}/user?username=#{user}", nil, {:Accept => "text/uri-list", :subjectid => subjectid}).sub("\n","")
    accounturi = `curl -Lk -X GET -H "Accept:text/uri-list" -H "subjectid:#{subjectid}" #{$user_service[:uri]}/user?username=#{user}`.chomp.sub("\n","")
    account = OpenTox::TBAccount.new(accounturi, subjectid)
    investigation_file = Dir["#{tmp}/i_*vestigation.txt"]
    investigation_file.each do |inv_file|
      text = File.read(inv_file, :encoding => "BINARY")
      #replace = text.gsub!(/TBU:U\d+/, account.ns_uri)
      replace = text.gsub!(/Comment \[Principal Investigator URI\]\t"TBU:U\d+"/ , "Comment \[Principal Investigator URI\]\t\"#{account.ns_uri}\"")
      replace = text.gsub!(/Comment \[Owner URI\]\t"TBU:U\d+"/ , "Comment \[Principal Investigator URI\]\t\"#{account.ns_uri}\"")
      File.open(inv_file, "wb") { |file| file.puts replace } if replace
    end
  rescue
    $logger.error "can not replace Principal Investigator to user: #{user} with subjectid: #{subjectid}"
  end
end

# monkey-patch for Rack::Utils.normalize_params. Enables multiple request params with the same name.
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
