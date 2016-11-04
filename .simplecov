require 'simplecov'
require 'coveralls'

SimpleCov.formatter = Coveralls::SimpleCov::Formatter
SimpleCov.start do
  add_filter 'lib/addressable/idna'
  add_filter 'lib/addressable/idna.rb'
end
