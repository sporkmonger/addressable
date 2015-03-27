source 'https://rubygems.org'

gemspec

group :development do
  gem 'yard'
  gem 'redcarpet', :platform => :mri_19
  gem 'rubyforge'
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
