require 'rubygems'
require 'opentox-ruby'
require 'config/config_ru'
run Sinatra::Application
set :raise_errors, false
set :show_exceptions, false