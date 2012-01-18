require 'rest-client'
['otlogger', 'environment', 'authorization', 'policy', 'helper'].each do |lib|
	require 'lib/' + lib
end