#require 'rubygems'
#require 'rack'
#require 'rack/contrib'
#require 'sinatra'
require './application.rb'
#require 'opentox-ruby'
#require 'config/config_ru'
run Sinatra::Application
set :raise_errors, true
set :show_exceptions, true
