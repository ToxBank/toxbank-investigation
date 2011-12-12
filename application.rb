require 'rubygems'
require 'fileutils'
#require 'rubyzip'

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

  def file
    File.join "./investigation", params[:id], params[:filename]
  end

  def next_id
	  id = Dir["./investigation/*"].collect{|f| File.basename(f).to_i}.sort.last
    id ? id + 1 : 0
  end

  def save
    halt 400, "Please submit data as multipart/form-data" unless request.form_data?
    halt 400, "Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless params[:file][:format] == 'application/zip' or params[:file][:format] == 'text/tab-separated-values'
    halt 400, "File #{params[:file][:filename]} exists already for investigation #{@id}. Please change the filename and submit again." if File.exists? params[:file][:filename]
    halt 400, "Only a single ISA-TAB investigation file allowed. #{Dir["#{dir}/i_*txt"]} exists already." if Dir["#{dir}/i_*txt"]
    `./java/ISA-validator-1.4/validate.sh #{params[:file][:tempfile]}`
    # TODO: return 400 if validation fails
    FileUtils.mkdir_p dir
    File.open(File.join(dir,params[:file][:filename]),"w+"){|f| f.puts params[:file][:tempfile].read}
    # TODO: avoid overwriting existing files, 
    `unzip #{File.join(dir,params[:file][:filename])}` if params[:file][:format] == 'application/zip' #filename.match(/\.zip$/)
    # TODO: create and store RDF
    response['Content-Type'] = 'text/uri-list'
    uri 
  end

end

before do
  params[:id] ? @id = params[:id] : @id = next_id 
  halt 404 unless File.exist? dir
  @accept = request.env['HTTP_ACCEPT']
  # TODO: A+A
end

# Query all investigations or get a list of all investigations
# Requests with a query parameter will perform a SPARQL query on all investigations
# @param query SPARQL query
# @return [application/sparql-results+json] Query result
# Requests without a query parameter return a list of all investigations
# @return [text/uri-list] List of investigations
get '/' do
  if params[:query]
    # TODO: implement RDF query
    #halt 501, "SPARQL query not yet implemented"
  else
    response['Content-Type'] = 'text/uri-list'
    uri_list
  end
end

# Create a new investigation from ISA-TAB files
# @param [Header] Content-type: multipart/form-data
# @param file Zipped investigation files in ISA-TAB format
# @return [text/uri-list] Investigation URI 
post '/' do
  save
end

# Get an investigation representation
# @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
# @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
get '/:id' do
  case @accept
  when "text/tab-separated-values"
    send_file Dir["./investigation/#{@id}/i_*txt"].first, :type => @accept
  when "text/uri-list"
    uri_list
  when "application/zip"
    # TODO: problems with multiple zip files uploaded
    send_file Dir["./investigation/#{@id}/*zip"].first
  when "application/sparql-results+json"
    # TODO: return all data in rdf
    halt 501, "SPARQL query not yet implemented"
  else
    halt 400, "Accept header #{@accept} not supported"
  end
end

# Add studies, assays or data to an investigation
# @param [Header] Content-type: multipart/form-data
# @param file Study, assay and data file (zip archive of ISA-TAB files or individual ISA-TAB files)
# @return [text/uri-list] New resource URI(s)
post '/:id' do
  save
end

# Delete an investigation
delete '/:id' do
  FileUtils.remove_entry_secure dir
end

# Get a study, assay, data representation
# @param [Header] one of text/tab-separated-values, application/sparql-results+json
# @return [text/tab-separated-values, application/sparql-results+json] Study, assay, data representation in ISA-TAB or RDF format
get '/:id/:filename'  do
  case @accept
  when "text/tab-separated-values"
    send_file file, :type => @accept
  when "application/sparql-results+json"
    # TODO: return all data in rdf
    halt 501, "SPARQL query not yet implemented"
  else
    halt 400, "Accept header #{@accept} not supported"
  end
end

# Delete an individual study, assay or data file
delete '/:id/:filename'  do
  File.delete file
  # TODO revalidate ISA-TAB
end
