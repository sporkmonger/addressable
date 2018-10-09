# frozen_string_literal: true

# encoding:utf-8
#--
# Copyright (C) Bob Aman
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
#++

require 'addressable/version'
require 'addressable/idna'
require 'public_suffix'

##
# Addressable is a library for processing links and URIs.
module Addressable
  ##
  # This is an implementation of a URI parser based on
  # <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>,
  # <a href="http://www.ietf.org/rfc/rfc3987.txt">RFC 3987</a>.
  class URI
    ##
    # Raised if something other than a uri is supplied.
    InvalidURIError = Class.new(StandardError)

    ##
    # Container for the character classes specified in
    # <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>.
    module CharacterClasses
      ALPHA      = 'a-zA-Z'.freeze
      DIGIT      = '0-9'.freeze
      GEN_DELIMS = '\\:\\/\\?\\#\\[\\]\\@'.freeze
      SUB_DELIMS = "\\!\\$\\&\\'\\(\\)\\*\\+\\,\\;\\=".freeze
      RESERVED   = GEN_DELIMS + SUB_DELIMS
      UNRESERVED = ALPHA + DIGIT + '\\-\\.\\_\\~'
      PCHAR      = UNRESERVED + SUB_DELIMS + '\\:\\@'
      SCHEME     = ALPHA + DIGIT + '\\-\\+\\.'
      HOST       = UNRESERVED + SUB_DELIMS + '\\[\\:\\]'
      AUTHORITY  = PCHAR
      PATH       = PCHAR + '\\/'
      QUERY      = PCHAR + '\\/\\?'
      FRAGMENT   = PCHAR + '\\/\\?'
    end

    SLASH     = '/'.freeze
    EMPTY_STR = ''.freeze

    URIREGEX = /^(([^:\/?#]+):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?$/

    PORT_MAPPING = {
      'http'     => 80,
      'https'    => 443,
      'ftp'      => 21,
      'tftp'     => 69,
      'sftp'     => 22,
      'ssh'      => 22,
      'svn+ssh'  => 22,
      'telnet'   => 23,
      'nntp'     => 119,
      'gopher'   => 70,
      'wais'     => 210,
      'ldap'     => 389,
      'prospero' => 1525
    }.freeze

    SELF_REF = '.'.freeze
    PARENT   = '..'.freeze

    RULE_2A              = /\/\.\/|\/\.$/
    RULE_2B_2C           = /\/([^\/]*)\/\.\.\/|\/([^\/]*)\/\.\.$/
    RULE_2D              = /^\.\.?\/?/
    RULE_PREFIXED_PARENT = /^\/\.\.?\/|^(\/\.\.?)+\/?$/

    class << self
      ##
      # Returns a URI object based on the parsed string.
      #
      # @param [String, Addressable::URI, #to_str] uri
      #   The URI string to parse.
      #   No parsing is performed if the object is already an
      #   <code>Addressable::URI</code>.
      #
      # @return [Addressable::URI] The parsed URI.

      def parse(uri)
        # If we were given nil, return nil.
        return nil unless uri
        # If a URI object is passed, just return itself.
        return uri.dup if uri.is_a?(self)

        # If a URI object of the Ruby standard library variety is passed,
        # convert it to a string, then parse the string.
        # We do the check this way because we don't want to accidentally
        # cause a missing constant exception to be thrown.
        uri = uri.to_s if uri.class.name =~ /^URI\b/

        # Otherwise, convert to a String
        unless uri.is_a? String
          begin
            uri = uri.to_str
          rescue TypeError, NoMethodError
            raise TypeError, "Can't convert #{uri.class} into String."
          end
        end

        # This Regexp supplied as an example in RFC 3986, and it works great.
        scan = uri.scan(URIREGEX)
        fragments = scan[0]
        scheme = fragments[1]
        authority = fragments[3]
        path = fragments[4]
        query = fragments[6]
        fragment = fragments[8]
        user = nil
        password = nil
        host = nil
        port = nil
        unless authority.nil?
          # The Regexp above doesn't split apart the authority.
          userinfo = authority[/^([^\[\]]*)@/, 1]
          unless userinfo.nil?
            user = userinfo.strip[/^([^:]*):?/, 1]
            password = userinfo.strip[/:(.*)$/, 1]
          end
          host = authority.sub(
            /^([^\[\]]*)@/, EMPTY_STR
          ).sub(
            /:([^:@\[\]]*?)$/, EMPTY_STR
          )
          port = authority[/:([^:@\[\]]*?)$/, 1]
        end
        port = nil if port == EMPTY_STR

        new(
          scheme: scheme,
          user: user,
          password: password,
          host: host,
          port: port,
          path: path,
          query: query,
          fragment: fragment
        )
      end

      ##
      # Converts an input to a URI. The input does not have to be a valid
      # URI — the method will use heuristics to guess what URI was intended.
      # This is not standards-compliant, merely user-friendly.
      #
      # @param [String, Addressable::URI, #to_str] uri
      #   The URI string to parse.
      #   No parsing is performed if the object is already an
      #   <code>Addressable::URI</code>.
      # @param [Hash] hints
      #   A <code>Hash</code> of hints to the heuristic parser.
      #   Defaults to <code>{:scheme => "http"}</code>.
      #
      # @return [Addressable::URI] The parsed URI.
      def heuristic_parse(uri, hints = {})
        # If we were given nil, return nil.
        return nil unless uri
        # If a URI object is passed, just return itself.
        return uri.dup if uri.is_a?(self)

        # If a URI object of the Ruby standard library variety is passed,
        # convert it to a string, then parse the string.
        # We do the check this way because we don't want to accidentally
        # cause a missing constant exception to be thrown.
        uri = uri.to_s if uri.class.name =~ /^URI\b/

        unless uri.respond_to?(:to_str)
          raise TypeError, "Can't convert #{uri.class} into String."
        end

        # Otherwise, convert to a String
        uri = uri.to_str.dup.strip
        hints = {
          scheme: 'http'
        }.merge(hints)
        case uri
        when /^http:\//i
          uri.sub!(/^http:\/+/i, 'http://')
        when /^https:\//i
          uri.sub!(/^https:\/+/i, 'https://')
        when /^feed:\/+http:\//i
          uri.sub!(/^feed:\/+http:\/+/i, 'feed:http://')
        when /^feed:\//i
          uri.sub!(/^feed:\/+/i, 'feed://')
        when %r[^file:/{4}]i
          uri.sub!(%r{^file:/+}i, 'file:////')
        when %r{^file://localhost/}i
          uri.sub!(%r{^file://localhost/+}i, 'file:///')
        when %r{^file:/+}i
          uri.sub!(%r{^file:/+}i, 'file:///')
        when /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
          uri.sub!(/^/, hints[:scheme] + '://')
        when /\A\d+\..*:\d+\z/
          uri = "#{hints[:scheme]}://#{uri}"
        end
        match = uri.match(URIREGEX)
        fragments = match.captures
        authority = fragments[3]
        if authority && !authority.empty?
          new_authority = authority.tr('\\', '/').gsub(/ /, '%20')
          # NOTE: We want offset 4, not 3!
          offset = match.offset(4)
          uri = uri.dup
          uri[offset[0]...offset[1]] = new_authority
        end
        parsed = parse(uri)
        if parsed.scheme =~ /^[^\/?#\.]+\.[^\/?#]+$/
          parsed = parse(hints[:scheme] + '://' + uri)
        end
        if parsed.path.include?('.')
          new_host = parsed.path[/^([^\/]+\.[^\/]*)/, 1]
          if new_host
            parsed.defer_validation do
              new_path = parsed.path.sub(
                Regexp.new('^' + Regexp.escape(new_host)), EMPTY_STR
              )
              parsed.host = new_host
              parsed.path = new_path
              parsed.scheme = hints[:scheme] unless parsed.scheme
            end
          end
        end
        parsed
      end

      ##
      # Converts a path to a file scheme URI. If the path supplied is
      # relative, it will be returned as a relative URI. If the path supplied
      # is actually a non-file URI, it will parse the URI as if it had been
      # parsed with <code>Addressable::URI.parse</code>. Handles all of the
      # various Microsoft-specific formats for specifying paths.
      #
      # @param [String, Addressable::URI, #to_str] path
      #   Typically a <code>String</code> path to a file or directory, but
      #   will return a sensible return value if an absolute URI is supplied
      #   instead.
      #
      # @return [Addressable::URI]
      #   The parsed file scheme URI or the original URI if some other URI
      #   scheme was provided.
      #
      # @example
      #   base = Addressable::URI.convert_path("/absolute/path/")
      #   uri = Addressable::URI.convert_path("relative/path")
      #   (base + uri).to_s
      #   #=> "file:///absolute/path/relative/path"
      #
      #   Addressable::URI.convert_path(
      #     "c:\\windows\\My Documents 100%20\\foo.txt"
      #   ).to_s
      #   #=> "file:///c:/windows/My%20Documents%20100%20/foo.txt"
      #
      #   Addressable::URI.convert_path("http://example.com/").to_s
      #   #=> "http://example.com/"
      def convert_path(path)
        # If we were given nil, return nil.
        return nil unless path
        # If a URI object is passed, just return itself.
        return path if path.is_a?(self)
        unless path.respond_to?(:to_str)
          raise TypeError, "Can't convert #{path.class} into String."
        end

        # Otherwise, convert to a String
        path = path.to_str.strip

        path.sub!(/^file:\/?\/?/, EMPTY_STR) if path =~ /^file:\/?\/?/
        path = SLASH + path if path =~ /^([a-zA-Z])[\|:]/
        uri = parse(path)

        if uri.scheme.nil?
          # Adjust windows-style uris
          uri.path.sub!(/^\/?([a-zA-Z])[\|:][\\\/]/) do
            "/#{Regexp.last_match(1).downcase}:/"
          end
          uri.path.gsub!(/\\/, SLASH)
          if File.exist?(uri.path) &&
             File.stat(uri.path).directory?
            uri.path.sub!(/\/$/, EMPTY_STR)
            uri.path = uri.path + '/'
          end

          # If the path is absolute, set the scheme and host.
          if uri.path =~ /^\//
            uri.scheme = 'file'
            uri.host = EMPTY_STR
          end
          uri.normalize!
        end

        uri
      end

      ##
      # Joins several URIs together.
      #
      # @param [String, Addressable::URI, #to_str] *uris
      #   The URIs to join.
      #
      # @return [Addressable::URI] The joined URI.
      #
      # @example
      #   base = "http://example.com/"
      #   uri = Addressable::URI.parse("relative/path")
      #   Addressable::URI.join(base, uri)
      #   #=> #<Addressable::URI:0xcab390 URI:http://example.com/relative/path>
      def join(*uris)
        uri_objects = uris.collect do |uri|
          unless uri.respond_to?(:to_str)
            raise TypeError, "Can't convert #{uri.class} into String."
          end

          uri.is_a?(self) ? uri : parse(uri.to_str)
        end
        result = uri_objects.shift.dup
        uri_objects.each do |uri|
          result.join!(uri)
        end

        result
      end

      ##
      # Percent encodes a URI component.
      #
      # @param [String, #to_str] component The URI component to encode.
      #
      # @param [String, Regexp] character_class
      #   The characters which are not percent encoded. If a <code>String</code>
      #   is passed, the <code>String</code> must be formatted as a regular
      #   expression character class. (Do not include the surrounding square
      #   brackets.)  For example, <code>"b-zB-Z0-9"</code> would cause
      #   everything but the letters 'b' through 'z' and the numbers '0' through
      #  '9' to be percent encoded. If a <code>Regexp</code> is passed, the
      #   value <code>/[^b-zB-Z0-9]/</code> would have the same effect. A set of
      #   useful <code>String</code> values may be found in the
      #   <code>Addressable::URI::CharacterClasses</code> module. The default
      #   value is the reserved plus unreserved character classes specified in
      #   <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>.
      #
      # @param [Regexp] upcase_encoded
      #   A string of characters that may already be percent encoded, and whose
      #   encodings should be upcased. This allows normalization of percent
      #   encodings for characters not included in the
      #   <code>character_class</code>.
      #
      # @return [String] The encoded component.
      #
      # @example
      #   Addressable::URI.encode_component("simple/example", "b-zB-Z0-9")
      #   => "simple%2Fex%61mple"
      #   Addressable::URI.encode_component("simple/example", /[^b-zB-Z0-9]/)
      #   => "simple%2Fex%61mple"
      #   Addressable::URI.encode_component(
      #     "simple/example", Addressable::URI::CharacterClasses::UNRESERVED
      #   )
      #   => "simple%2Fexample"
      def encode_component(component, character_class = CharacterClasses::RESERVED + CharacterClasses::UNRESERVED,
                           upcase_encoded = '')
        return nil if component.nil?

        unless component.is_a? String
          begin
            component = if component.is_a?(Symbol) ||
                           component.is_a?(Numeric) ||
                           component.is_a?(TrueClass) ||
                           component.is_a?(FalseClass)
                          component.to_s
                        else
                          component.to_str
                        end
          rescue TypeError, NoMethodError
            raise TypeError, "Can't convert #{component.class} into String."
          end
        end

        unless [String, Regexp].include?(character_class.class)
          raise TypeError, "Expected String or Regexp, got #{character_class.inspect}"
        end

        if character_class.is_a?(String)
          character_class = /[^#{character_class}]/
        end
        # We can't perform regexps on invalid UTF sequences, but
        # here we need to, so switch to ASCII.
        component = component.dup
        component.force_encoding(Encoding::ASCII_8BIT)
        # Avoiding gsub! because there are edge cases with frozen strings
        component = component.gsub(character_class) do |sequence|
          (sequence.unpack('C*').map { |c| '%' + format('%02x', c).upcase }).join
        end
        unless upcase_encoded.empty?
          component = component.gsub(/%(#{upcase_encoded.chars.map do |char|
            char.unpack('C*').map { |c| format('%02x', c) }.join
          end.join('|')})/i, &:upcase)
        end

        component
      end

      ##
      # Unencodes any percent encoded characters within a URI component.
      # This method may be used for unencoding either components or full URIs,
      # however, it is recommended to use the <code>unencode_component</code>
      # alias when unencoding components.
      #
      # @param [String, Addressable::URI, #to_str] uri
      #   The URI or component to unencode.
      #
      # @param [Class] return_type
      #   The type of object to return.
      #   This value may only be set to <code>String</code> or
      #   <code>Addressable::URI</code>. All other values are invalid. Defaults
      #   to <code>String</code>.
      #
      # @param [String] leave_encoded
      #   A string of characters to leave encoded. If a percent encoded character
      #   in this list is encountered then it will remain percent encoded.
      #
      # @return [String, Addressable::URI]
      #   The unencoded component or URI.
      #   The return type is determined by the <code>return_type</code>
      #   parameter.
      def unencode(uri, return_type = String, leave_encoded = '')
        return nil if uri.nil?

        unless uri.is_a? String
          begin
            uri = uri.to_str
          rescue NoMethodError, TypeError
            raise TypeError, "Can't convert #{uri.class} into String."
          end
        end
        unless [String, ::Addressable::URI].include?(return_type)
          raise TypeError, "Expected Class (String or Addressable::URI), got #{return_type.inspect}"
        end

        uri = uri.dup
        # Seriously, only use UTF-8. I'm really not kidding!
        uri.force_encoding('utf-8')
        leave_encoded = leave_encoded.dup.force_encoding('utf-8')
        result = uri.gsub(/%[0-9a-f]{2}/iu) do |sequence|
          c = sequence[1..3].to_i(16).chr
          c.force_encoding('utf-8')
          leave_encoded.include?(c) ? sequence : c
        end
        result.force_encoding('utf-8')
        return result if return_type == String

        Addressable::URI.parse(result) if return_type == ::Addressable::URI
      end

      ##
      # Normalizes the encoding of a URI component.
      #
      # @param [String, #to_str] component The URI component to encode.
      #
      # @param [String, Regexp] character_class
      #   The characters which are not percent encoded. If a <code>String</code>
      #   is passed, the <code>String</code> must be formatted as a regular
      #   expression character class. (Do not include the surrounding square
      #   brackets.)  For example, <code>"b-zB-Z0-9"</code> would cause
      #   everything but the letters 'b' through 'z' and the numbers '0'
      #   through '9' to be percent encoded. If a <code>Regexp</code> is passed,
      #   the value <code>/[^b-zB-Z0-9]/</code> would have the same effect. A
      #   set of useful <code>String</code> values may be found in the
      #   <code>Addressable::URI::CharacterClasses</code> module. The default
      #   value is the reserved plus unreserved character classes specified in
      #   <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>.
      #
      # @param [String] leave_encoded
      #   When <code>character_class</code> is a <code>String</code> then
      #   <code>leave_encoded</code> is a string of characters that should remain
      #   percent encoded while normalizing the component; if they appear percent
      #   encoded in the original component, then they will be upcased ("%2f"
      #   normalized to "%2F") but otherwise left alone.
      #
      # @return [String] The normalized component.
      #
      # @example
      #   Addressable::URI.normalize_component("simpl%65/%65xampl%65", "b-zB-Z")
      #   => "simple%2Fex%61mple"
      #   Addressable::URI.normalize_component(
      #     "simpl%65/%65xampl%65", /[^b-zB-Z]/
      #   )
      #   => "simple%2Fex%61mple"
      #   Addressable::URI.normalize_component(
      #     "simpl%65/%65xampl%65",
      #     Addressable::URI::CharacterClasses::UNRESERVED
      #   )
      #   => "simple%2Fexample"
      #   Addressable::URI.normalize_component(
      #     "one%20two%2fthree%26four",
      #     "0-9a-zA-Z &/",
      #     "/"
      #   )
      #   => "one two%2Fthree&four"
      def normalize_component(
        component,
        character_class = CharacterClasses::RESERVED + CharacterClasses::UNRESERVED,
        leave_encoded = ''
      )
        return nil if component.nil?

        unless component.is_a? String
          begin
            component = component.to_str
          rescue NoMethodError, TypeError
            raise TypeError, "Can't convert #{component.class} into String."
          end
        end

        unless [String, Regexp].include?(character_class.class)
          raise TypeError, "Expected String or Regexp, got #{character_class.inspect}"
        end

        if character_class.is_a?(String)
          leave_re = unless leave_encoded.empty?
                       character_class = "#{character_class}%" unless character_class.include?('%')

                       "|%(?!#{leave_encoded.chars.map do |char|
                         seq = char.unpack('C*').map { |c| format('%02x', c) }.join
                         [seq.upcase, seq.downcase]
                       end.flatten.join('|')})"
                     end

          character_class = /[^#{character_class}]#{leave_re}/
        end
        # We can't perform regexps on invalid UTF sequences, but
        # here we need to, so switch to ASCII.
        component = component.dup
        component.force_encoding(Encoding::ASCII_8BIT)
        unencoded = unencode_component(component, String, leave_encoded)
        begin
          encoded = encode_component(
            Addressable::IDNA.unicode_normalize_kc(unencoded),
            character_class,
            leave_encoded
          )
        rescue ArgumentError
          encoded = encode_component(unencoded)
        end
        encoded.force_encoding(Encoding::UTF_8)

        encoded
      end

      ##
      # Percent encodes any special characters in the URI.
      #
      # @param [String, Addressable::URI, #to_str] uri
      #   The URI to encode.
      #
      # @param [Class] return_type
      #   The type of object to return.
      #   This value may only be set to <code>String</code> or
      #   <code>Addressable::URI</code>. All other values are invalid. Defaults
      #   to <code>String</code>.
      #
      # @return [String, Addressable::URI]
      #   The encoded URI.
      #   The return type is determined by the <code>return_type</code>
      #   parameter.
      def encode(uri, return_type = String)
        return nil if uri.nil?

        unless uri.is_a? String
          begin
            uri = uri.to_str
          rescue NoMethodError, TypeError
            raise TypeError, "Can't convert #{uri.class} into String."
          end
        end

        unless [String, ::Addressable::URI].include?(return_type)
          raise TypeError,
                "Expected Class (String or Addressable::URI), got #{return_type.inspect}"
        end
        uri_object = uri.is_a?(self) ? uri : parse(uri)
        encoded_uri = Addressable::URI.new(
          scheme: encode_component(uri_object.scheme, Addressable::URI::CharacterClasses::SCHEME),
          authority: encode_component(uri_object.authority, Addressable::URI::CharacterClasses::AUTHORITY),
          path: encode_component(uri_object.path, Addressable::URI::CharacterClasses::PATH),
          query: encode_component(uri_object.query, Addressable::URI::CharacterClasses::QUERY),
          fragment: encode_component(uri_object.fragment, Addressable::URI::CharacterClasses::FRAGMENT)
        )

        return encoded_uri.to_s if return_type == String

        encoded_uri if return_type == ::Addressable::URI
      end

      ##
      # Normalizes the encoding of a URI. Characters within a hostname are
      # not percent encoded to allow for internationalized domain names.
      #
      # @param [String, Addressable::URI, #to_str] uri
      #   The URI to encode.
      #
      # @param [Class] return_type
      #   The type of object to return.
      #   This value may only be set to <code>String</code> or
      #   <code>Addressable::URI</code>. All other values are invalid. Defaults
      #   to <code>String</code>.
      #
      # @return [String, Addressable::URI]
      #   The encoded URI.
      #   The return type is determined by the <code>return_type</code>
      #   parameter.
      def normalized_encode(uri, return_type = String)
        unless uri.is_a? String
          begin
            uri = uri.to_str
          rescue NoMethodError, TypeError
            raise TypeError, "Can't convert #{uri.class} into String."
          end
        end

        unless [String, ::Addressable::URI].include?(return_type)
          raise TypeError,
                "Expected Class (String or Addressable::URI), got #{return_type.inspect}"
        end
        uri_object = uri.is_a?(self) ? uri : parse(uri)
        components = {
          scheme: unencode_component(uri_object.scheme),
          user: unencode_component(uri_object.user),
          password: unencode_component(uri_object.password),
          host: unencode_component(uri_object.host),
          port: (uri_object.port.nil? ? nil : uri_object.port.to_s),
          path: unencode_component(uri_object.path),
          query: unencode_component(uri_object.query),
          fragment: unencode_component(uri_object.fragment)
        }
        components.each do |key, value|
          next if value.nil?

          begin
            components[key] = Addressable::IDNA.unicode_normalize_kc(value.to_str)
          rescue ArgumentError
            # Likely a malformed UTF-8 character, skip unicode normalization
            components[key] = value.to_str
          end
        end
        encoded_uri = Addressable::URI.new(
          scheme: encode_component(components[:scheme], Addressable::URI::CharacterClasses::SCHEME),
          user: encode_component(components[:user], Addressable::URI::CharacterClasses::UNRESERVED),
          password: encode_component(components[:password], Addressable::URI::CharacterClasses::UNRESERVED),
          host: components[:host],
          port: components[:port],
          path: encode_component(components[:path], Addressable::URI::CharacterClasses::PATH),
          query: encode_component(components[:query], Addressable::URI::CharacterClasses::QUERY),
          fragment: encode_component(components[:fragment], Addressable::URI::CharacterClasses::FRAGMENT)
        )

        return encoded_uri.to_s if return_type == String

        encoded_uri if return_type == ::Addressable::URI
      end

      ##
      # Encodes a set of key/value pairs according to the rules for the
      # <code>application/x-www-form-urlencoded</code> MIME type.
      #
      # @param [#to_hash, #to_ary] form_values
      #   The form values to encode.
      #
      # @param [TrueClass, FalseClass] sort
      #   Sort the key/value pairs prior to encoding.
      #   Defaults to <code>false</code>.
      #
      # @return [String]
      #   The encoded value.
      def form_encode(form_values, sort = false)
        if form_values.respond_to?(:to_hash)
          form_values = form_values.to_hash.to_a
        elsif form_values.respond_to?(:to_ary)
          form_values = form_values.to_ary
        else
          raise TypeError, "Can't convert #{form_values.class} into Array."
        end

        form_values = form_values.each_with_object([]) do |(key, value), accu|
          if value.is_a?(Array)
            value.each do |v|
              accu << [key.to_s, v.to_s]
            end
          else
            accu << [key.to_s, value.to_s]
          end
        end

        if sort
          # Useful for OAuth and optimizing caching systems
          form_values = form_values.sort
        end
        escaped_form_values = form_values.map do |(key, value)|
          # Line breaks are CRLF pairs
          [
            encode_component(
              key.gsub(/(\r\n|\n|\r)/, "\r\n"),
              CharacterClasses::UNRESERVED
            ).gsub('%20', '+'),
            encode_component(
              value.gsub(/(\r\n|\n|\r)/, "\r\n"),
              CharacterClasses::UNRESERVED
            ).gsub('%20', '+')
          ]
        end
        escaped_form_values.map do |(key, value)|
          "#{key}=#{value}"
        end.join('&')
      end

      ##
      # Decodes a <code>String</code> according to the rules for the
      # <code>application/x-www-form-urlencoded</code> MIME type.
      #
      # @param [String, #to_str] encoded_value
      #   The form values to decode.
      #
      # @return [Array]
      #   The decoded values.
      #   This is not a <code>Hash</code> because of the possibility for
      #   duplicate keys.
      def form_unencode(encoded_value)
        unless encoded_value.respond_to?(:to_str)
          raise TypeError, "Can't convert #{encoded_value.class} into String."
        end

        encoded_value = encoded_value.to_str
        split_values = encoded_value.split('&').map do |pair|
          pair.split('=', 2)
        end
        split_values.map do |(key, value)|
          [
            key ? unencode_component(key.gsub('+', '%20')).gsub(/(\r\n|\n|\r)/, "\n") : nil,
            value ? unencode_component(value.gsub('+', '%20')).gsub(/(\r\n|\n|\r)/, "\n") : nil
          ]
        end
      end

      ##
      # Resolves paths to their simplest form.
      #
      # @param [String] path The path to normalize.
      #
      # @return [String] The normalized path.
      def normalize_path(path)
        # Section 5.2.4 of RFC 3986

        return nil if path.nil?

        normalized_path = path.dup
        begin
          mod = nil
          mod ||= normalized_path.gsub!(RULE_2A, SLASH)

          pair = normalized_path.match(RULE_2B_2C)
          if pair
            parent = pair[1]
            current = pair[2]
          end
          if pair && ((parent != SELF_REF && parent != PARENT) ||
              (current != SELF_REF && current != PARENT))
            mod ||= normalized_path.gsub!(
              Regexp.new(
                "/#{Regexp.escape(parent.to_s)}/\\.\\./|(/#{Regexp.escape(current.to_s)}/\\.\\.$)"
              ), SLASH
            )
          end

          mod ||= normalized_path.gsub!(RULE_2D, EMPTY_STR)
          # Non-standard, removes prefixed dotted segments from path.
          mod ||= normalized_path.gsub!(RULE_PREFIXED_PARENT, SLASH)
        end until mod.nil?

        normalized_path
      end

      alias unescape unencode
      alias unencode_component unencode
      alias unescape_component unencode
      alias escape encode
    end
  end
end
