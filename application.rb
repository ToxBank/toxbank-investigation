require 'rubygems'
#gem "opentox-ruby", "~> 3"
#require 'opentox-ruby'
require 'fileutils'

helpers do

  def uri
    @id ? url_for("/#{@id}", :full) : "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
  end

  def uri_list 
    @id ? d = "./investigation/#{@id}/*" : d = "./investigation/*"
    Dir[d].collect{|f| url_for(d.sub(/^\./,'').sub(/\*/,'') + File.basename(f), :full)}.join("\n") + "\n"
  end

  def dir
    File.join "./investigation", @id.to_s
  end

  def next_id
	  id = Dir["./investigation/*"].collect{|f| File.basename(f).to_i}.sort.last
    id ? id + 1 : 0
  end

  def save
    FileUtils.mkdir_p dir
    File.open(File.join(dir,params[:file][:filename]),"w+"){|f| f.puts params[:file][:tempfile].read}
    response['Content-Type'] = 'text/uri-list'
    uri 
  end

end

before do
  @accept = request.env['HTTP_ACCEPT']
  #raise "store subject-id in dataset-object, not in params" if params.has_key?(:subjectid) and @subjectid==nil
  #params.delete(:subjectid) 
  #OpenTox::Authorization.check_policy(uri, @subjectid)
  @id = params[:id]
end

get '/investigation' do
  response['Content-Type'] = 'text/uri-list'
  uri_list
end

post '/investigation' do
  @id = next_id 
  save
end

get '/investigation/:id' do
  @id = params[:id]
  uri_list
end

get '/investigation/:id/:file' do
  @id = params[:id]
  send_file File.join(dir,params[:file])
end

post '/investigation/:id' do
  @id = params[:id]
  FileUtils.remove_entry_secure dir
  save
end

delete '/investigation/:id' do
  @id = params[:id]
  FileUtils.remove_entry_secure dir
end
