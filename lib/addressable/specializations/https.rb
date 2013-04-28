require "addressable/uri"
require "addressable/specializations/http"

module Addressable
  class URI
    ##
    # An https URI
    class HTTPS < HTTP
      ##
      # Associates processing of https: URIs with this class.
      #
      # @return [String] Returns 'https'.
      def self.scheme
        return "https"
      end

      ##
      # URIs with an https: scheme are IP-based.
      #
      # @return [TrueClass] Returns true.
      def self.ip_based?
        return true
      end

      ##
      # URIs with an https: scheme are IP-based.
      #
      # @return [TrueClass] Returns true.
      def ip_based?
        return true
      end

      ##
      # URIs with an https: scheme use 443 as their default port.
      #
      # @return [Integer] Returns 443.
      def self.default_port
        return 443
      end
    end
  end
end
