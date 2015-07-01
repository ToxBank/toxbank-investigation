# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "toxbank-investigation"
  s.version     = File.read("./VERSION")
  s.authors     = ["Christoph Helma","Denis Gebele","Micha Rautenberg"]
  s.email       = ["helma@in-silico.ch","gebele@in-silico.ch","rautenberg@in-silico.ch"]
  s.homepage    = "http://github.com/ToxBank/toxbank-investigation"
  s.summary     = %q{Toxbank investigation service}
  s.description = %q{Toxbank investigation service}
  s.license     = 'GPL-3'
  #s.platform    = Gem::Platform::CURRENT

  s.rubyforge_project = "toxbank-investigation"

  s.files         = `git ls-files`.split("\n")
  s.required_ruby_version = '~> 2.0.0'

  # specify any dependencies here:
  s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency 'mongo', '~> 2.0'

  # external requirements
  ["git", "zip", "java", "curl", "wget", "dos2unix"].each{|r| s.requirements << r}
  s.post_install_message = "Run toxbank-investigation-install to set up your service."
end
