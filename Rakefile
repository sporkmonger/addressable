require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/packagetask'
require 'rake/gempackagetask'
require 'spec/rake/spectask'

require File.join(File.dirname(__FILE__), 'lib', 'addressable', 'version')

PKG_DISPLAY_NAME   = 'Addressable'
PKG_NAME           = PKG_DISPLAY_NAME.downcase
PKG_VERSION        = Addressable::VERSION::STRING
PKG_FILE_NAME      = "#{PKG_NAME}-#{PKG_VERSION}"

RELEASE_NAME       = "REL #{PKG_VERSION}"

RUBY_FORGE_PROJECT = PKG_NAME
RUBY_FORGE_USER    = "sporkmonger"
RUBY_FORGE_PATH    = "/var/www/gforge-projects/#{RUBY_FORGE_PROJECT}"
RUBY_FORGE_URL     = "http://#{RUBY_FORGE_PROJECT}.rubyforge.org/"

PKG_SUMMARY        = "URI Implementation"
PKG_DESCRIPTION    = <<-TEXT
Addressable is a replacement for the URI implementation that is part of
Ruby's standard library. It more closely conforms to the relevant RFCs and
adds support for IRIs and URI templates.
TEXT

desc "generates .gemspec file"
task :gemspec do
  spec = Gem::Specification.new do |p|
    p.name = 'addressable'
    p.version = PKG_VERSION

    p.summary = PKG_SUMMARY
    p.description = PKG_DESCRIPTION

    p.author = 'Bob Aman'
    p.email  = 'bob@sporkmonger.com'
    p.homepage = 'http://github.com/mislav/addressable'
    p.rubyforge_project = nil

    p.files = FileList['Rakefile', '{bin,lib,tasks,spec}/**/*', 'README*', 'LICENSE*', 'CHANGELOG*'] & `git ls-files`.split

    p.executables = Dir['bin/*'].map { |f| File.basename(f) }

    p.has_rdoc = true
  end
  
  spec_string = spec.to_ruby
  
  begin
    Thread.new { eval("$SAFE = 3\n#{spec_string}", binding) }.join 
  rescue
    abort "unsafe gemspec: #{$!}"
  else
    File.open("#{spec.name}.gemspec", 'w') { |file| file.write spec_string }
  end
end

PKG_FILES = FileList[
    "lib/**/*", "spec/**/*", "vendor/**/*",
    "tasks/**/*", "website/**/*",
    "[A-Z]*", "Rakefile"
].exclude(/database\.yml/).exclude(/[_\.]git$/)

RCOV_ENABLED = (RUBY_PLATFORM != "java" && RUBY_VERSION =~ /^1\.8/)
task :default => "spec"

WINDOWS = (RUBY_PLATFORM =~ /mswin|win32|mingw|bccwin|cygwin/) rescue false
SUDO = WINDOWS ? '' : ('sudo' unless ENV['SUDOLESS'])

Dir['tasks/**/*.rake'].each { |rake| load rake }
