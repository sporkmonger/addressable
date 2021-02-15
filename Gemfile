# frozen_string_literal: true

source 'https://rubygems.org'

gemspec(path: __FILE__ == "(eval)" ? ".." : ".")

group :test do
  gem 'rspec', '~> 3.8'
  gem 'rspec-its', '~> 1.3'
end

group :coverage do
  gem "coveralls", require: false, platforms: :mri
  gem "simplecov", require: false
end

group :development do
  gem 'launchy', '~> 2.4', '>= 2.4.3'
  gem 'redcarpet', :platform => :mri_19
  gem 'yard'
end

group :test, :development do
  gem 'memory_profiler'
  gem "rake", "> 10.0"
  # Used to test compatibility.
  gem 'rack-mount', git: 'https://github.com/sporkmonger/rack-mount.git', require: 'rack/mount'

  if RUBY_VERSION.start_with?('2.0', '2.1')
    gem 'rack', '< 2', :require => false
  else
    gem 'rack', :require => false
  end
end

gem "idn-ruby", platform: :mri
