source 'https://rubygems.org'

group :development do
  gem 'launchy'
  gem 'yard'
  gem 'redcarpet', :platform => :mri_19
  gem 'rubyforge'
end

group :test, :development do
  gem 'coveralls', :require => false
end

gem 'idn', :platform => :mri_18
gem 'idn-ruby', :platform => :mri_19

platforms :ruby_18 do
  gem 'rest-client', '~> 1.8.0'
end

platforms :rbx do
  gem 'rubysl-openssl', '2.2.1'
end

gemspec
