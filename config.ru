require 'opentox-server'
require './application.rb'
Bundler.require
run Sinatra::Application
set :raise_errors, false
set :show_exceptions, false
