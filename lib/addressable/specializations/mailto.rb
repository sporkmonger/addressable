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

module Addressable
  class URI
    ##
    # A mailto URI
    class MailTo < self
      ##
      # Associates processing of mailto: URIs with this class.
      #
      # @return [String] Returns 'mailto'.
      def self.scheme
        return "mailto"
      end

      ##
      # URIs with a mailto: scheme are not IP-based and do not have a default
      # port.
      #
      # @return [NilClass] Returns nil.
      def self.default_port
        return nil
      end

      ##
      # URIs with a mailto: scheme are not IP-based.
      #
      # @return [FalseClass] Returns false.
      def self.ip_based?
        return false
      end

      ##
      # URIs with a mailto: scheme are not IP-based.
      #
      # @return [FalseClass] Returns false.
      def ip_based?
        return false
      end

      ##
      # Returns an array of email addresses for the To field.
      #
      # @return [Array]
      #   The email addresses which should be placed in the To field.
      def to
        @to ||= (begin
          addresses = []
          addresses = addresses.concat(self.path.split(",", -1))
          self.query and self.query_values(Array).each do |(key, value)|
            if key.downcase == "to"
              addresses = addresses.concat(value.split(",", -1))
            end
          end
          addresses.uniq
        end)
      end

      ##
      # Returns an array of email addresses for the Cc field.
      #
      # @return [Array]
      #   The email addresses which should be placed in the Cc field.
      def cc
        @cc ||= (begin
          addresses = []
          self.query and self.query_values(Array).each do |(key, value)|
            if key.downcase == "cc"
              addresses = addresses.concat(value.split(",", -1))
            end
          end
          addresses.uniq
        end)
      end

      ##
      # Returns an array of email addresses for the Bcc field.
      #
      # @return [Array]
      #   The email addresses which should be placed in the Bcc field.
      def bcc
        @bcc ||= (begin
          addresses = []
          self.query and self.query_values(Array).each do |(key, value)|
            if key.downcase == "bcc"
              addresses = addresses.concat(value.split(",", -1))
            end
          end
          addresses.uniq
        end)
      end

      ##
      # Returns the subject line, unencoded.
      #
      # @return [String]
      #   The subject line of the message, unencoded. Returns nil if missing.
      def subject
        @subject ||= (begin
          subject = nil
          self.query and self.query_values(Array).each do |(key, value)|
            if key.downcase == "subject"
              subject = value
              break
            end
          end
          Addressable::URI.unencode_component(subject)
        end)
      end

      ##
      # Returns the message body, unencoded.
      #
      # @return [String]
      #   The message body, unencoded. Returns nil if missing.
      def body
        @body ||= (begin
          body = nil
          self.query and self.query_values(Array).each do |(key, value)|
            if key.downcase == "body"
              body = value
              break
            end
          end
          Addressable::URI.unencode_component(body)
        end)
      end

      ##
      # The query component for this URI, normalized according to the rules
      # given in RFC 6068.
      #
      # @return [String] The query component, normalized.
      def normalized_query
        self.query && @normalized_query ||= (begin
          stripped_headers = [
            "from",
            "date",
            "apparently-to",
            "resent-date",
            "resent-from",
            "resent-sender",
            "resent-to",
            "resent-cc",
            "resent-bcc",
            "resent-message-id",
            "return-path",
            "received",
            "mime-version",
            "content-type",
            "content-transfer-encoding",
            "content-id",
            "content-description",
            "content-disposition",
            "content-length"
          ]
          ((self.query_values(Array).reject do |(key, value)|
            stripped_headers.include?(key.downcase) ||
            key.downcase =~ /^content\-/ ||
            key.downcase =~ /^resent\-/
          end).map do |(key, value)|
            Addressable::URI.normalize_component(
              "#{key}=#{value}",
              Addressable::URI::CharacterClasses::QUERY.sub("\\&", "")
            )
          end).join("&")
        end)
      end

      ##
      # Returns a normalized URI object. For mailto: links, it will merge
      # multiple To fields and strip unsafe header values.
      #
      # @return [Addressable::URI::MailTo] The normalized URI.
      def normalize
        naive_normalized_uri = self.class.parse(super.to_s)
        naive_normalized_uri.path = naive_normalized_uri.to.join(",")
        naive_normalized_uri.query and naive_normalized_uri.query_values = (
          naive_normalized_uri.query_values(Array).reject do |(key, value)|
            key.downcase == "to"
          end
        )
        naive_normalized_uri.query = nil if naive_normalized_uri.query == ""
        naive_normalized_uri
      end
    end
  end
end
