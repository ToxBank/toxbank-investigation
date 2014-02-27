#@markup markdown
ToxBank Investigation
=====================
Investigation service for ToxBank. 

Installation:
-------------
  Dependencies: ruby 2.0.x, git, zip, java, curl, wget

    gem install toxbank-investigation
    toxbank-investigation-install # service setup, configuration and webserver start

Development:
------------

  get the development branch:

    git clone git@github.com:ToxBank/toxbank-investigation.git  
    cd toxbank-investigation
    git checkout development


  edit `Gemfile`:  
  uncomment and edit if you want to use github versions of opentox gems

      gem 'opentox-server', :git => "git://github.com/opentox/opentox-server", :branch => "development"
      gem 'opentox-client', :git => "git://github.com/opentox/opentox-client", :branch => "development"

  uncomment and edit if you want to use local installations of opentox gems

      gem 'opentox-server', :path => "~/opentox-server"
      gem "opentox-client", :path => "~/opentox-client"

  install the service via bundler gem 

    bundle install
    bin/toxbank-investigation-install
    # Do you want to start the webserver? (y/n)
    # Answer "n" 
    unicorn -c unicorn.rb # starts server as defined in unicorn.rb
    # unicorn -h: more options


see also https://github.com/opentox/opentox-server

see also https://github.com/opentox/opentox-client

Documentation
-------------
* ToxBank API documentation with examples see [ToxBank API wiki](http://api.toxbank.net/index.php/Investigation)
* Code documentation at [RubyDoc.info](http://rubydoc.info/github/ToxBank/toxbank-investigation/development/frames)
