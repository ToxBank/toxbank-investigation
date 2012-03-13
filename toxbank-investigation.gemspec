# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "toxbank-investigation"
  s.version     = "0.0.1pre"
  s.authors     = ["Christoph Helma","Denis Gebele","Micha Rautenberg"]
  s.email       = ["helma@in-silico.ch","gebele@in-silico.ch","rautenenberg@in-silico.ch"]
  s.homepage    = "http://github.com/ToxBank/toxbank-investigation"
  s.summary     = %q{Toxbank investigation service}
  s.description = %q{Toxbank investigation service}
  s.license     = 'GPL-3'
  #s.platform    = Gem::Platform::CURRENT

  s.rubyforge_project = "toxbank-investigation"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  #s.require_paths = ["lib"]
  s.required_ruby_version = '>= 1.9.2'

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-server"

  # external requirements
  ["git", "zip", "java", "curl", "wget"].each{|r| s.requirements << r}
  s.post_install_message = "Run toxbank-investigation-install to set up your service"
end
