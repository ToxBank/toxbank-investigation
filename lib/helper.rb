helpers do

  # Authentification
  def protected!(subjectid)
    if env["session"]
      unless authorized?(subjectid)
        flash[:notice] = "You don't have access to this section: "
        redirect back
      end
    elsif !env["session"] && subjectid
      unless authorized?(subjectid)
        LOGGER.debug "URI not authorized: clean: " + clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}").to_s + " full: #{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']} with request: #{request.env['REQUEST_METHOD']}"
        #raise OpenTox::NotAuthorizedError.new "Not authorized"
        halt 401, "Not authorized"
      end
    else
      halt 401, "Not authorized" unless authorized?(subjectid)
    end
 end

  #Check Authorization for URI with method and subjectid.
  def authorized?(subjectid)
    request_method = request.env['REQUEST_METHOD']
    uri = clean_uri("#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}#{request.env['REQUEST_URI']}")
    request_method = "GET" if request_method == "POST" &&  uri =~ /\/model\/\d+\/?$/
    return OpenTox::Authorization.authorized?(uri, request_method, subjectid)
  end

  #cleans URI from querystring and file-extension. Sets port 80 to emptystring
  # @param [String] uri
  def clean_uri(uri)
    uri = uri.sub(" ", "%20")          #dirty hacks => to fix
    uri = uri[0,uri.index("InChI=")] if uri.index("InChI=")
    out = URI.parse(uri)
    out.path = out.path[0, out.path.length - (out.path.reverse.rindex(/\/{1}\d+\/{1}/))] if out.path.index(/\/{1}\d+\/{1}/)  #cuts after /id/ for a&a
    out.path = out.path.split('.').first #cut extension
    port = (out.scheme=="http" && out.port==80)||(out.scheme=="https" && out.port==443) ? "" : ":#{out.port.to_s}"
    "#{out.scheme}://#{out.host}#{port}#{out.path.chomp("/")}" #"
  end

  #unprotected uri for login
  def login_requests
    return env['REQUEST_URI'] =~ /\/login$/
   end

  def uri_available?(urlStr)
    url = URI.parse(urlStr)
    subjectidstr = @subjectid ? "?subjectid=#{CGI.escape @subjectid}" : ""
    Net::HTTP.start(url.host, url.port) do |http|
      return http.head("#{url.request_uri}#{subjectidstr}").code == "200"
    end
  end

  def get_subjectid
    begin
      subjectid = nil
      subjectid = session[:subjectid] if session[:subjectid]
      subjectid = params[:subjectid]  if params[:subjectid] and !subjectid
      subjectid = request.env['HTTP_SUBJECTID'] if request.env['HTTP_SUBJECTID'] and !subjectid
      # see http://rack.rubyforge.org/doc/SPEC.html
      subjectid = CGI.unescape(subjectid) if subjectid.include?("%23")
      @subjectid = subjectid
    rescue
      @subjectid = nil
    end
  end
  def get_extension
    @accept = request.env['HTTP_ACCEPT']
    @accept = 'application/rdf+xml' if @accept == '*/*' or @accept == '' or @accept.nil?
    extension = File.extname(request.path_info)
    unless extension.empty?
      case extension.gsub(".","")
      when "html"
        @accept = 'text/html'
      when "yaml"
        @accept = 'application/x-yaml'
      when "csv"
        @accept = 'text/csv'
      when "rdfxml"
        @accept = 'application/rdf+xml'
      when "xls"
        @accept = 'application/ms-excel'
      when "sdf"
        @accept = 'chemical/x-mdl-sdfile'
      when "css"
        @accept = 'text/css'
      else
        # raise OpenTox::NotFoundError.new "File format #{extension} not supported."
      end
    end
  end
end

before do
  get_subjectid()
  #git status
  get_extension()
  unless !AA_SERVER or login_requests or CONFIG[:authorization][:free_request].include?(env['REQUEST_METHOD'])
    protected!(@subjectid)
  end
end
