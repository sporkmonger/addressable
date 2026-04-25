# frozen_string_literal: true

module Addressable
  autoload :VERSION, File.expand_path("addressable/version", __dir__)
  autoload :IDNA, File.expand_path("addressable/idna", __dir__)
  autoload :URI, File.expand_path("addressable/uri", __dir__)
  autoload :Template, File.expand_path("addressable/template", __dir__)
end
