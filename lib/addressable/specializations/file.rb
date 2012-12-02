require "addressable/uri"

module Addressable
  class URI
    ##
    # A file URI
    class File < self
      def self.scheme
        return "file"
      end
    end
  end
end
