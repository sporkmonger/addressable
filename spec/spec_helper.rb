require 'rspec/its'

begin
  require 'coveralls'
  Coveralls.wear! do
    add_filter "spec/"
  end
rescue LoadError
  warn "warning: coveralls gem not found; skipping Coveralls"
  require 'simplecov'
  SimpleCov.start do
    add_filter "spec/"
  end
end

RSpec.configure do |config|
  config.warnings = true
end
