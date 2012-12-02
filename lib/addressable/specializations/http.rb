require "addressable/uri"

module Addressable
  class URI
    ##
    # An http URI
    class HTTP < self
      def self.scheme
        return "http"
      end

      def self.default_port
        return 80
      end
    end
  end
end
