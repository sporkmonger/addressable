require "addressable/uri"
require "addressable/specializations/http"

module Addressable
  class URI
    ##
    # An https URI
    class HTTPS < HTTP
      def self.scheme
        return "https"
      end

      def self.default_port
        return 443
      end
    end
  end
end
