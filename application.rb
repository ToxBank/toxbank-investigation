require 'rubygems'
require 'fileutils'
require 'rack'
require 'rack/contrib'
require 'sinatra'
require 'sinatra/url_for'

helpers do

  def uri
    params[:id] ? url_for("/#{params[:id]}", :full) : "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
  end

  def uri_list 
    params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
    Dir[d].collect{|f|  url_for(f.sub(/\.\/investigation/,''),:full) if f.match(/\.txt$/) }.compact.sort.join("\n") + "\n"
  end

  def dir
    File.join "./investigation", params[:id].to_s
  end

  def file
    File.join "./investigation", params[:id], params[:filename]
  end

  def next_id
	  id = Dir["./investigation/*"].collect{|f| File.basename(f).to_i}.sort.last
    id ? id + 1 : 0
  end

  def save
    # lock tmp dir
    tmp = File.join dir,"tmp"
    halt 423, "Importing another submission. Please try again later." if File.exists? tmp
    halt 400, "Please submit data as multipart/form-data" unless request.form_data?
    halt 400, "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless params[:file][:type]== 'application/zip' or params[:file][:type]== 'text/tab-separated-values'
    # move existing ISA-TAB files to tmp
    FileUtils.mkdir_p tmp
    FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
    # overwrite existing files with new submission
    File.open(File.join(tmp,params[:file][:filename]),"w+"){|f| f.puts params[:file][:tempfile].read}
    `unzip -o #{File.join(tmp,params[:file][:filename])} -d #{tmp}` if params[:file][:type] == 'application/zip' #filename.match(/\.zip$/)
    # validate ISA-TAB
    validator = File.join(File.dirname(File.expand_path __FILE__), "java/ISA-validator-1.4")
    validator_call = "java -Xms256m -Xmx1024m -XX:PermSize=64m -XX:MaxPermSize=128m -cp #{File.join validator, "isatools_deps.jar"} org.isatools.isatab.manager.SimpleManager validate #{File.expand_path tmp} #{File.join validator, "config/default-config"}"
    result = `validator_call`
    unless result.chomp.empty?
      FileUtils.remove_entry tmp 
      halt 400, "ISA-TAB validation failed:\n"+result
    end
    # if everything is fine move ISA-TAB files back to original dir
    FileUtils.cp Dir[File.join(tmp,"*.txt")], dir
    # TODO: git commit
    # newfiles = `cd investigation; git ls-files --others --directory`
    # `cd investigation; git add #{newfiles}`
    # `cd investigation; git commit -am "submission from #{request.ip}`
    FileUtils.remove_entry tmp 
    zipfile = File.join dir, "investigation_#{params[:id]}.zip"
    `zip -j #{zipfile} #{dir}/*.txt`
    # TODO: create and store RDF
    # rdf = `isa2rdf`
    # `4s-import ToxBank #{rdf}`
    response['Content-Type'] = 'text/uri-list'
    uri 
  end

end

before do
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
get '/?' do
  if params[:query]
    # TODO: implement RDF query
    #`4s-query ToxBank #{params[:query]}`
    halt 501, "SPARQL query not yet implemented"
  else
    response['Content-Type'] = 'text/uri-list'
    uri_list
  end
end

# Create a new investigation from ISA-TAB files
# @param [Header] Content-type: multipart/form-data
# @param file Zipped investigation files in ISA-TAB format
# @return [text/uri-list] Investigation URI 
post '/?' do
  params[:id] = next_id
  save
end

# Get an investigation representation
# @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
# @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
get '/:id' do
  case @accept
  when "text/tab-separated-values"
    send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
  when "text/uri-list"
    uri_list
  when "application/zip"
    send_file File.join dir, "investigation_#{params[:id]}.zip"
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
  FileUtils.remove_entry dir
  # TODO: git commit
  #`cd investigation; git commit -am "#{dir} deleted from #{request.ip}"`
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
  # TODO: git commit
  # `cd investigation; git commit -am "#{file} deleted from #{request.ip}"`
  # TODO revalidate ISA-TAB
end
