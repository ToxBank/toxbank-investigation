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
    # TODO: validate isa-tab
    # TODO: create and store RDF
    FileUtils.mkdir_p dir
    File.open(File.join(dir,params[:file][:filename]),"w+"){|f| f.puts params[:file][:tempfile].read}
    response['Content-Type'] = 'text/uri-list'
    uri 
  end

end

before do
  @accept = request.env['HTTP_ACCEPT']
  params[:id] ? @id = params[:id] : @id = next_id 
  # TODO: A+A
end

# Query all investigations or get a list of all investigations
# Requests with a query parameter will perform a SPARQL query on all investigations
# @param [Header] Accept: one of application/sparql-results+xml, application/sparql-results+json
# @param query SPARQL query
# @return [application/sparql-results+xml, application/sparql-results+json] Query result
# Requests without a query parameter return a list of all investigations
# @return [text/uri-list] List of investigations
get '/' do
  if params[:query]
    # TODO: implement RDF query
  else
    response['Content-Type'] = 'text/uri-list'
    uri_list
  end
end

# Create a new investigation from ISA-TAB files
# @param [Header] Content-type: multipart/form-data
# @param file Investigation in ISA-TAB format
# @return [text/uri-list] Investigation URI 
post '/' do
  save
end

# Get an investigation
# @param [Header] Accept: one of text/uri-list, application/x-tgz, application/sparql-results+json
# @return [text/uri-list, application/x-tgz, application/sparql-results+json] Investigation in the requested format
get '/:id' do
  case @accept
  when "text/uri-list"
    uri_list
  when "application/x-tgz"
    # TODO: return all data as tar.gz
  when "application/sparql-results+json"
    # TODO: return all data in rdf
  end
end

# Create a new version of an investigation
# Will create a new investigation which is linked to the original investigation, the original investigation will remain intact
# @param [Header] Content-type: multipart/form-data
# @param file Investigation in ISA-TAB format
# @return [text/uri-list] New investigation URI 
post '/:id' do
  # TODO
end

# Delete an investigation
delete '/:id' do
  FileUtils.remove_entry_secure dir
  # TODO: delete RDF data
end

# Get a list of studies of an investigation
# @return [text/uri-list] List of study URIs 
get '/:id/study'  do
  # TODO
end

# Add a study to an investigation
# @param [Header] Content-type: multipart/form-data
# @param file Study in ISA-TAB format
# @return [text/uri-list] Study URI 
post '/:id/study' do
  # TODO
end

# Get a study 
# @param [Header] Accept: one of application/x-tgz, application/sparql-results+json
# @return [application/x-tgz, application/sparql-results+json] Study files or RDF
get '/:id/study/:study_id' do
  case @accept
  when "text/tab-separated-values"
    # TODO
  when "application/sparql-results+json"
    # TODO
  end
end

# Add an assay to a study
# @param [Header] Content-type: multipart/form-data
# @param file Study in ISA-TAB format
# @return [text/uri-list] Assay URI 
post '/:id/study/:study_id' do
  # TODO
end

# Get a list of assays of a study
# @return [text/uri-list] List of assay URIs 
get '/:id/study/:study_id/assay'  do
  # TODO
end

# Get an assay
# @param [Header] Accept: one of text/tab-separated-values, application/sparql-results+json
# @return [text/tab-separated-values, application/sparql-results+json] Assay file or RDF
get '/:id/study/:study_id/assay/:assay_id' do
  # TODO
end

# Get a list of data files or links to datasets for an assay
# @return [text/uri-list] List of file/dataset URIs 
get '/:id/study/:study_id/assay/:assay_id/file' do
  # TODO
end

# Get a data file
# @return Data file (ISA-TAB, CEL, ...)
get '/:id/study/:study_id/assay/:assay_id/file/:file_id' do
  # TODO
end
