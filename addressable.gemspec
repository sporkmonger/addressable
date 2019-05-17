# -*- encoding: utf-8 -*-
# stub: addressable 2.6.0 ruby lib

Gem::Specification.new do |s|
  s.name = "addressable"
  s.version = "2.6.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib"]
  s.authors = ["Bob Aman"]
  s.date = "2019-01-18"
  s.description = "Addressable is a replacement for the URI implementation that is part of\nRuby's standard library. It more closely conforms to the relevant RFCs and\nadds support for IRIs and URI templates.\n"
  s.email = "bob@sporkmonger.com"
  s.extra_rdoc_files = ["README.md"]
  s.files = ["CHANGELOG.md", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "data/unicode.data", "lib/addressable", "lib/addressable.rb", "lib/addressable/idna", "lib/addressable/idna.rb", "lib/addressable/idna/native.rb", "lib/addressable/idna/pure.rb", "lib/addressable/template.rb", "lib/addressable/uri.rb", "lib/addressable/version.rb", "spec/addressable", "spec/addressable/idna_spec.rb", "spec/addressable/net_http_compat_spec.rb", "spec/addressable/rack_mount_compat_spec.rb", "spec/addressable/security_spec.rb", "spec/addressable/template_spec.rb", "spec/addressable/uri_spec.rb", "spec/spec_helper.rb", "tasks/clobber.rake", "tasks/gem.rake", "tasks/git.rake", "tasks/metrics.rake", "tasks/rspec.rake", "tasks/yard.rake"]
  s.homepage = "https://github.com/sporkmonger/addressable"
  s.licenses = ["Apache-2.0"]
  s.rdoc_options = ["--main", "README.md"]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0")
  s.rubygems_version = "2.5.1"
  s.summary = "URI Implementation"

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<public_suffix>, ["< 4.0", ">= 2.0.2"])
      s.add_development_dependency(%q<bundler>, ["< 3.0", ">= 1.0"])
    else
      s.add_dependency(%q<public_suffix>, ["< 4.0", ">= 2.0.2"])
      s.add_dependency(%q<bundler>, ["< 3.0", ">= 1.0"])
    end
  else
    s.add_dependency(%q<public_suffix>, ["< 4.0", ">= 2.0.2"])
    s.add_dependency(%q<bundler>, ["< 3.0", ">= 1.0"])
  end

  if s.respond_to?(:metadata)
    s.metadata = {
      "bug_tracker_uri" => "https://github.com/sporkmonger/addressable/issues",
      "changelog_uri" => "https://github.com/sporkmonger/addressable/blob/master/CHANGELOG.md",
      "documentation_uri" => "http://rubydoc.info/gems/addressable",
      "homepage_uri" => "https://github.com/sporkmonger/addressable",
      "source_code_uri" => "https://github.com/sporkmonger/addressable"
    }
  end
end
