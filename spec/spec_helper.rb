# frozen_string_literal: true

require 'bundler/setup'
require 'rspec/its'

begin
  require 'coveralls'
  Coveralls.wear! do
    add_filter "spec/"
    add_filter "vendor/"
  end
rescue LoadError
  warn "warning: coveralls gem not found; skipping Coveralls"
  require 'simplecov'
  SimpleCov.start do
    add_filter "spec/"
    add_filter "vendor/"
  end
end if Gem.loaded_specs.key?("simplecov")

class TestHelper
  def self.is_jruby?
    Object.const_defined? :JRUBY_VERSION
  end

  def self.is_mri?
    RUBY_ENGINE == "ruby"
  end

  def self.is_windows?
    RUBY_DESCRIPTION =~ /mswin|ming|cygwin/
  end

  def self.native_supported?
    is_mri? && !is_windows?
  end
end

# Warnings raised by Addressable's own code, or by its specs, fail the run.
# Warnings from other gems are still printed but are otherwise ignored.
module StrictWarnings
  PROJECT_PATHS = %r{\A#{Regexp.escape(File.expand_path("..", __dir__))}/(?:lib|spec)/}

  def self.warnings
    @warnings ||= []
  end

  def warn(message, *args)
    StrictWarnings.warnings << message if message =~ PROJECT_PATHS
    super
  end
  ruby2_keywords(:warn) if respond_to?(:ruby2_keywords, true)
end

if defined?(Warning) && Warning.respond_to?(:warn)
  if Warning.respond_to?(:[]=)
    categories = Warning.respond_to?(:categories) ?
      Warning.categories : [:deprecated, :experimental, :performance]
    categories.each do |category|
      begin
        Warning[category] = true
      rescue ArgumentError
        # This Ruby doesn't have this category.
      end
    end
  end
  Warning.extend(StrictWarnings)
end

RSpec.configure do |config|
  config.warnings = true
  config.filter_run_when_matching :focus

  config.after(:suite) do
    unless StrictWarnings.warnings.empty?
      raise "Warnings from lib/ or spec/:\n" + StrictWarnings.warnings.uniq.join
    end
  end
end
