# -*- encoding: utf-8 -*-
# stub: addressable 2.3.6 ruby lib

Gem::Specification.new do |s|
  s.name = "addressable"
  s.version = "2.3.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Bob Aman"]
  s.date = "2014-08-12"
  s.description = "Addressable is a replacement for the URI implementation that is part of\nRuby's standard library. It more closely conforms to the relevant RFCs and\nadds support for IRIs and URI templates.\n"
  s.email = "bob@sporkmonger.com"
  s.extra_rdoc_files = ["README.md"]
  s.files = ["CHANGELOG.md", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "data/unicode.data", "lib/addressable", "lib/addressable/idna", "lib/addressable/idna.rb", "lib/addressable/idna/native.rb", "lib/addressable/idna/pure.rb", "lib/addressable/template.rb", "lib/addressable/uri.rb", "lib/addressable/version.rb", "spec/addressable", "spec/addressable/idna_spec.rb", "spec/addressable/net_http_compat_spec.rb", "spec/addressable/template_spec.rb", "spec/addressable/uri_spec.rb", "spec/spec_helper.rb", "tasks/clobber.rake", "tasks/gem.rake", "tasks/git.rake", "tasks/metrics.rake", "tasks/rspec.rake", "tasks/rubyforge.rake", "tasks/yard.rake", "website/index.html"]
  s.homepage = "http://addressable.rubyforge.org/"
  s.licenses = ["Apache License 2.0"]
  s.rdoc_options = ["--main", "README.md"]
  s.rubyforge_project = "addressable"
  s.rubygems_version = "2.2.2"
  s.summary = "URI Implementation"

  s.add_development_dependency(%q<rake>, [">= 0.7.3"])
  s.add_development_dependency(%q<rspec>, [">= 2.9.0", "~> 2.9"])
  s.add_development_dependency(%q<launchy>, [">= 0.3.2"])
end
