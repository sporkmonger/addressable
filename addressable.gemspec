# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{addressable}
  s.version = "2.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Bob Aman"]
  s.date = %q{2009-09-27}
  s.description = %q{Addressable is a replacement for the URI implementation that is part of
Ruby's standard library. It more closely conforms to the relevant RFCs and
adds support for IRIs and URI templates.
}
  s.email = %q{bob@sporkmonger.com}
  s.files = ["Rakefile", "lib/addressable/idna.rb", "lib/addressable/template.rb", "lib/addressable/uri.rb", "lib/addressable/version.rb", "tasks/clobber.rake", "tasks/gem.rake", "tasks/git.rake", "tasks/metrics.rake", "tasks/rdoc.rake", "tasks/rubyforge.rake", "tasks/spec.rake", "spec/addressable/idna_spec.rb", "spec/addressable/template_spec.rb", "spec/addressable/uri_spec.rb", "spec/data/rfc3986.txt", "README", "LICENSE", "CHANGELOG"]
  s.homepage = %q{http://github.com/mislav/addressable}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.5}
  s.summary = %q{URI Implementation}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
