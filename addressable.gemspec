# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{addressable}
  s.version = "2.2.8"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Bob Aman"]
  s.date = %q{2012-05-02}
  s.description = %q{Addressable is a replacement for the URI implementation that is part of
Ruby's standard library. It more closely conforms to the relevant RFCs and
adds support for IRIs and URI templates.
}
  s.email = %q{bob@sporkmonger.com}
  s.extra_rdoc_files = ["README.md"]
  s.files = ["lib/addressable", "lib/addressable/idna", "lib/addressable/idna/native.rb", "lib/addressable/idna/pure.rb", "lib/addressable/idna.rb", "lib/addressable/template.rb", "lib/addressable/uri.rb", "lib/addressable/version.rb", "spec/addressable", "spec/addressable/idna_spec.rb", "spec/addressable/net_http_compat_spec.rb", "spec/addressable/template_spec.rb", "spec/addressable/uri_spec.rb", "tasks/clobber.rake", "tasks/gem.rake", "tasks/git.rake", "tasks/metrics.rake", "tasks/rspec.rake", "tasks/rubyforge.rake", "tasks/yard.rake", "website/index.html", "CHANGELOG.md", "Gemfile", "Gemfile.lock", "LICENSE.txt", "Rakefile", "README.md"]
  s.homepage = %q{http://addressable.rubyforge.org/}
  s.rdoc_options = ["--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{addressable}
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{URI Implementation}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<rake>, [">= 0.7.3"])
      s.add_development_dependency(%q<rspec>, [">= 2.9.0"])
      s.add_development_dependency(%q<launchy>, [">= 0.3.2"])
    else
      s.add_dependency(%q<rake>, [">= 0.7.3"])
      s.add_dependency(%q<rspec>, [">= 2.9.0"])
      s.add_dependency(%q<launchy>, [">= 0.3.2"])
    end
  else
    s.add_dependency(%q<rake>, [">= 0.7.3"])
    s.add_dependency(%q<rspec>, [">= 2.9.0"])
    s.add_dependency(%q<launchy>, [">= 0.3.2"])
  end
end
