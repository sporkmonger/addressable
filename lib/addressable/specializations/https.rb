# coding: utf-8
# Copyright (C) 2006-2013 Bob Aman
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.


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
