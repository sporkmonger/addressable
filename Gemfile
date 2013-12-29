source 'https://rubygems.org'

group :development do
  gem 'launchy'
  gem 'yard'
  gem 'redcarpet', :platform => :mri_19
  gem 'rubyforge'
end

group :test, :development do
  gem 'rake', '>= 0.7.3'
  gem 'rspec', '>= 2.9.0'
  gem 'coveralls', :require => false
end

gem 'idn', :platform => :mri_18
gem 'idn-ruby', :platform => :mri_19

platforms :mri_18 do
  gem 'mime-types', '~> 1.25'
end

platforms :rbx do
  gem 'rubysl', '~> 2.0'
  gem 'rubinius-coverage'
end

gemspec
