require 'rubygems'
require 'fileutils'
require 'rack'
require 'rack/contrib'
require 'sinatra'
require 'sinatra/url_for'
require 'grit'
require 'spreadsheet'
require 'roo'
require 'uri'


helpers do

  def uri
    params[:id] ? url_for("/#{params[:id]}", :full) : "#{request.env['rack.url_scheme']}://#{request.env['HTTP_HOST']}"
  end

  def uri_list 
    params[:id] ? d = "./investigation/#{params[:id]}/*" : d = "./investigation/*"
    Dir[d].collect{|f|  url_for(f.sub(/\.\/investigation/,''),:full) if f.match(/\.txt$/) or f.match(/\d$/) }.compact.sort.join("\n") + "\n"
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
    puts params.inspect
    halt 400, "Mime type #{params[:file][:type]} not supported. Please submit data as zip archive (application/zip) or as tab separated text (text/tab-separated-values)" unless params[:file][:type]== 'application/zip' or params[:file][:type]== 'text/tab-separated-values'
    # move existing ISA-TAB files to tmp
    FileUtils.mkdir_p tmp
    FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
    # overwrite existing files with new submission
    File.open(File.join(tmp,params[:file][:filename]),"w+"){|f| f.puts params[:file][:tempfile].read}
    `unzip -o #{File.join(tmp,params[:file][:filename])} -d #{tmp}; mv #{tmp}/*/*.txt #{tmp}/` if params[:file][:type] == 'application/zip'
    # validate ISA-TAB
    validator = File.join(File.dirname(File.expand_path __FILE__), "java/ISA-validator-1.4")
    validator_call = "java -Xms256m -Xmx1024m -XX:PermSize=64m -XX:MaxPermSize=128m -cp #{File.join validator, "isatools_deps.jar"} org.isatools.isatab.manager.SimpleManager validate #{File.expand_path tmp} #{File.join validator, "config/default-config"}"
    puts validator_call
    result = `#{validator_call} 2>&1`
    if result.split("\n").last.match(/ERROR/) # isavalidator exit code is 0 even if validation fails
      FileUtils.remove_entry tmp 
      FileUtils.remove_entry dir
      halt 400, "ISA-TAB validation failed:\n"+result
    end
    # if everything is fine move ISA-TAB files back to original dir
    FileUtils.cp Dir[File.join(tmp,"*.txt")], dir
    # git commit
    newfiles = `cd investigation; git ls-files --others --exclude-standard --directory`
    `cd investigation; git add #{newfiles}`
    params[:file][:type] == 'application/zip' ? action = "created" : action = "modified"
    `cd investigation; git commit -am "investigation #{params[:id]} #{action} by #{request.ip}"`
    # create new zipfile
    zipfile = File.join dir, "investigation_#{params[:id]}.zip"
    `zip -j #{zipfile} #{dir}/*.txt`
    FileUtils.remove_entry tmp  # unlocks tmp
    # create and store RDF
    #`cd java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d ../#{dir} 2>/dev/null | grep -v WARN > ../#{dir}/tmp.n3` # warnings go to stdout
    puts `cd java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d ../#{dir} -o ../#{dir}/tmp.n3` # warnings go to stdout
    puts `4s-import -v ToxBank #{dir}/tmp.n3`
    FileUtils.rm "#{dir}/tmp.n3"
    response['Content-Type'] = 'text/uri-list'
    uri
  end

  def convert_xls
    # convert xls to ISA-TAB
    tmp = File.join dir, "tmp"
    FileUtils.mkdir_p tmp
    File.open(File.join(tmp, params[:file][:filename]), "w+"){|f| f.puts params[:file][:tempfile].read}
    # use Excelx.new instead of Excel.new if your file is a .xlsx
    xls = Excel.new(File.join(tmp, params[:file][:filename])) if params[:file][:filename].match(/.xls$/)
    #xls = Excelx.new(File.join(tmp, params[:file][:filename])) if params[:file][:filename].match(/.xlsx$/)
    xls.sheets.each_with_index do |sh, idx|
      name = sh.to_s
      xls.default_sheet = xls.sheets[idx]
      1.upto(xls.last_row) do |ro|
        1.upto(xls.last_column) do |co|
          unless (co == xls.last_column)
            File.open(File.join(tmp, name + ".txt"), "a+"){|f| f.print "#{xls.cell(ro, co)}\t"}
          else
            File.open(File.join(tmp, name + ".txt"), "a+"){|f| f.print "#{xls.cell(ro, co)}\n"}
          end
        end
      end
    end   
    # validate ISA-TAB
    validator = File.join(File.dirname(File.expand_path __FILE__), "java/ISA-validator-1.4")
    validator_call = "java -Xms256m -Xmx1024m -XX:PermSize=64m -XX:MaxPermSize=128m -cp #{File.join validator, "isatools_deps.jar"} org.isatools.isatab.manager.SimpleManager validate #{File.expand_path tmp} #{File.join validator, "config/default-config"}"
    result = `#{validator_call} 2>&1`
    if result.split("\n").last.match(/ERROR/) # isavalidator exit code is 0 even if validation fails
      FileUtils.remove_entry tmp 
      FileUtils.remove_entry dir
      halt 400, "ISA-TAB validation failed:\n"+result
    end
    # if everything is fine move ISA-TAB files back to original dir
    FileUtils.cp Dir[File.join(tmp,"*.txt")], dir
    # git commit
    newfiles = `cd investigation; git ls-files --others --exclude-standard --directory`
    `cd investigation; git add #{newfiles}`
    params[:file][:type] == 'application/zip' ? action = "created" : action = "modified"
    `cd investigation; git commit -am "investigation #{params[:id]} #{action} by #{request.ip}"`
    # create new zipfile
    zipfile = File.join dir, "investigation_#{params[:id]}.zip"
    `zip -j #{zipfile} #{dir}/*.txt`
    FileUtils.remove_entry tmp  # unlocks tmp
    # create and store RDF
    #`cd java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d ../#{dir} 2>/dev/null | grep -v WARN > ../#{dir}/tmp.n3` # warnings go to stdout
    #puts `cd java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d ../#{dir} -o ../#{dir}/tmp.n3` # warnings go to stdout
    puts `cd java && java -jar isa2rdf-0.0.1-SNAPSHOT.jar -d ../#{dir} -o ../#{dir}/#{params[:id]}.n3` # warnings go to stdout
    #puts `4s-import -v ToxBank #{dir}/tmp.n3`
    #puts `4s-import -v ToxBank #{dir}/#{params[:id]}.n3`
    puts `4s-import -v ToxBank --model http://localhost/#{params[:id]} #{dir}/#{params[:id]}.n3`
    #FileUtils.rm "#{dir}/tmp.n3"
    FileUtils.rm "#{dir}/#{params[:id]}.n3"
    response['Content-Type'] = 'text/uri-list'
    uri
  end
  
end

before do
  halt 404 unless File.exist? dir
  @accept = request.env['HTTP_ACCEPT']
  response['Content-Type'] = @accept
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
    response['Content-type'] = "application/sparql-results+json"
    # set base uri and prefixes for query
    @base ="http://onto.toxbank.net/isa/TEST/"
    @prefix ="PREFIX isa: <http://onto.toxbank.net/isa/>PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>PREFIX dc:<http://purl.org/dc/elements/1.1/>PREFIX owl: <http://www.w3.org/2002/07/owl#>PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>PREFIX dcterms: <http://purl.org/dc/terms/>"
    # sparql in 4store
    params.each{|k, v| @query = CGI.unescape(v)}
    # use it like: "http://localhost/?query=SELECT * WHERE {?x ?p ?o}" in your browser
    @result = `4s-query --soft-limit -1 ToxBank -f json -b '#{@base}' '#{@prefix} #{@query}'`
    @result.chomp
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
  # TODO check free disc space + Limit 4store to 10% free disc space
  params[:id] = next_id
  case params[:file][:type]
  when "application/vnd.ms-excel"
    convert_xls
  #when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    #convert_xls
  else
    save
  end
end

# Get an investigation representation
# @param [Header] Accept: one of text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json
# @return [text/tab-separated-values, text/uri-list, application/zip, application/sparql-results+json] Investigation in the requested format
get '/:id' do
  halt 404 unless File.exist? dir # not called in before filter???
  case @accept
  when "text/tab-separated-values"
    send_file Dir["./investigation/#{params[:id]}/i_*txt"].first, :type => @accept
  when "text/uri-list"
    uri_list
  when "application/zip"
    send_file File.join dir, "investigation_#{params[:id]}.zip"
  when "application/sparql-results+json"
    # TODO: return all data in rdf string
    #
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
  # git commit
  `cd investigation; git commit -am "#{dir} deleted by #{request.ip}"`
  # TODO: updata RDF
  `4s-delete-model ToxBank #{uri}`
  response['Content-Type'] = 'text/plain'
  "investigation #{params[:id]} deleted"
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
  # revalidate ISA-TAB
  # lock tmp dir
  tmp = File.join dir,"tmp"
  halt 423, "Working on another submission. Please try again later." if File.exists? tmp
  # move existing ISA-TAB files to tmp
  FileUtils.mkdir_p tmp
  FileUtils.cp Dir[File.join(dir,"*.txt")], tmp
  File.delete File.join(tmp,params[:filename])
  # validate ISA-TAB
  validator = File.join(File.dirname(File.expand_path __FILE__), "java/ISA-validator-1.4")
  validator_call = "java -Xms256m -Xmx1024m -XX:PermSize=64m -XX:MaxPermSize=128m -cp #{File.join validator, "isatools_deps.jar"} org.isatools.isatab.manager.SimpleManager validate #{File.expand_path tmp} #{File.join validator, "config/default-config"}"
  result = `validator_call`
  unless result.chomp.empty?
    FileUtils.remove_entry tmp 
    halt 400, "ISA-TAB validation failed:\n"+result
  end
  # if everything is fine move ISA-TAB files back to original dir
  FileUtils.rm Dir[File.join(dir,"*.txt")]
  FileUtils.cp Dir[File.join(tmp,"*.txt")], dir
  # git commit
  `cd investigation; git commit -am "#{params[:filename]} deleted by #{request.ip}"`
  # create new zipfile
  zipfile = File.join dir, "investigation_#{params[:id]}.zip"
  `zip -j #{zipfile} #{dir}/*.txt`
  FileUtils.remove_entry tmp 
  # TODO: updata RDF
  response['Content-Type'] = 'text/plain'
  "#{params[:filename]} deleted from investigation #{params[:id]}"
end
