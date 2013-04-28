require "addressable/uri"

module Addressable
  class URI
    ##
    # A file URI
    class File < self
      ##
      # Associates processing of file: URIs with this class.
      #
      # @return [String] Returns 'file'.
      def self.scheme
        return "file"
      end

      ##
      # URIs with a file: scheme are not IP-based.
      #
      # @return [FalseClass] Returns false.
      def self.ip_based?
        return false
      end

      ##
      # URIs with a file: scheme are not IP-based.
      #
      # @return [FalseClass] Returns false.
      def ip_based?
        return false
      end
    end
  end
end
