require 'rest-client'
['otlogger', 'environment', 'helper'].each do |lib|
#['otlogger', 'environment', 'authorization', 'policy', 'helper'].each do |lib|
	require File.join(File.dirname(__FILE__), lib)
end
