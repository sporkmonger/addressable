source 'https://rubygems.org'

gemspec

gem 'rake', '~> 10.4', '>= 10.4.2'

group :test do
  gem 'rspec', '~> 3.0'
  gem 'rspec-its', '~> 1.1'
end

group :development do
  gem 'launchy', '~> 2.4', '>= 2.4.3'
  gem 'redcarpet', :platform => :mri_19
  gem 'rubyforge'
  gem 'yard'
end

group :test, :development do
  gem 'simplecov', :require => false
  gem 'coveralls', :require => false, :platforms => [
    :ruby_19, :ruby_20, :ruby_21, :rbx, :jruby
  ]
end

gem 'idn', :platform => :mri_18
gem 'idn-ruby', :platform => :mri_19

platforms :rbx do
  gem 'rubysl-openssl', '2.2.1'
end
