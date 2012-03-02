require 'rubygems'
require 'bundler'
Bundler.require
require './application.rb'
run Sinatra::Application
set :raise_errors, false
set :show_exceptions, false
