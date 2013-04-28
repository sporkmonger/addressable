require "addressable/uri"

module Addressable
  class URI
    ##
    # An http URI
    class HTTP < self
      ##
      # Associates processing of http: URIs with this class.
      #
      # @return [String] Returns 'http'.
      def self.scheme
        return "http"
      end

      ##
      # URIs with an http: scheme are IP-based.
      #
      # @return [TrueClass] Returns true.
      def self.ip_based?
        return true
      end

      ##
      # URIs with an http: scheme are IP-based.
      #
      # @return [TrueClass] Returns true.
      def ip_based?
        return true
      end

      ##
      # URIs with an https: scheme use 80 as their default port.
      #
      # @return [Integer] Returns 80.
      def self.default_port
        return 80
      end
    end
  end
end
