# coding:utf-8
#--
# Addressable, Copyright (c) 2006-2008 Bob Aman
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '/..')))
$:.uniq!

require "addressable/version"
require "addressable/idna"

module Addressable
  ##
  # This is an implementation of a URI parser based on
  # <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>,
  # <a href="http://www.ietf.org/rfc/rfc3987.txt">RFC 3987</a>.
  class URI
    ##
    # Raised if something other than a uri is supplied.
    class InvalidURIError < StandardError
    end

    ##
    # Raised if an invalid method option is supplied.
    class InvalidOptionError < StandardError
    end

    ##
    # Raised if an invalid method option is supplied.
    class InvalidTemplateValue < StandardError
    end

    ##
    # Container for the character classes specified in
    # <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>.
    module CharacterClasses
      ALPHA = "a-zA-Z"
      DIGIT = "0-9"
      GEN_DELIMS = "\\:\\/\\?\\#\\[\\]\\@"
      SUB_DELIMS = "\\!\\$\\&\\'\\(\\)\\*\\+\\,\\;\\="
      RESERVED = GEN_DELIMS + SUB_DELIMS
      UNRESERVED = ALPHA + DIGIT + "\\-\\.\\_\\~"
      PCHAR = UNRESERVED + SUB_DELIMS + "\\:\\@"
      SCHEME = ALPHA + DIGIT + "\\-\\+\\."
      AUTHORITY = PCHAR
      PATH = PCHAR + "\\/"
      QUERY = PCHAR + "\\/\\?"
      FRAGMENT = PCHAR + "\\/\\?"
    end

    ##
    # Returns a URI object based on the parsed string.
    #
    # @param [String, Addressable::URI, #to_str] uri
    #   The URI string to parse.  No parsing is performed if the object is
    #   already an <tt>Addressable::URI</tt>.
    #
    # @return [Addressable::URI] The parsed URI.
    def self.parse(uri)
      # If we were given nil, return nil.
      return nil unless uri
      # If a URI object is passed, just return itself.
      return uri if uri.kind_of?(self)
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      # Otherwise, convert to a String
      uri = uri.to_str

      # If a URI object of the Ruby standard library variety is passed,
      # convert it to a string, then parse the string.
      # We do the check this way because we don't want to accidentally
      # cause a missing constant exception to be thrown.
      if uri.class.name =~ /^URI\b/
        uri = uri.to_s
      end

      # This Regexp supplied as an example in RFC 3986, and it works great.
      uri_regex =
        /^(([^:\/?#]+):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/
      scan = uri.scan(uri_regex)
      fragments = scan[0]
      return nil if fragments.nil?
      scheme = fragments[1]
      authority = fragments[3]
      path = fragments[4]
      query = fragments[6]
      fragment = fragments[8]
      userinfo = nil
      user = nil
      password = nil
      host = nil
      port = nil
      if authority != nil
        # The Regexp above doesn't split apart the authority.
        userinfo = authority[/^([^\[\]]*)@/, 1]
        if userinfo != nil
          user = userinfo.strip[/^([^:]*):?/, 1]
          password = userinfo.strip[/:(.*)$/, 1]
        end
        host = authority.gsub(/^([^\[\]]*)@/, "").gsub(/:([^:@\[\]]*?)$/, "")
        port = authority[/:([^:@\[\]]*?)$/, 1]
      end
      if port == ""
        port = nil
      end

      return Addressable::URI.new(
        :scheme => scheme,
        :user => user,
        :password => password,
        :host => host,
        :port => port,
        :path => path,
        :query => query,
        :fragment => fragment
      )
    end

    ##
    # Converts an input to a URI.  The input does not have to be a valid
    # URI — the method will use heuristics to guess what URI was intended.
    # This is not standards-compliant, merely user-friendly.
    #
    # @param [String, Addressable::URI, #to_str] uri
    #   The URI string to parse.  No parsing is performed if the object is
    #   already an <tt>Addressable::URI</tt>.
    # @param [Hash] hints
    #   A <tt>Hash</tt> of hints to the heuristic parser.  Defaults to
    #   <tt>{:scheme => "http"}</tt>.
    #
    # @return [Addressable::URI] The parsed URI.
    def self.heuristic_parse(uri, hints={})
      # If we were given nil, return nil.
      return nil unless uri
      # If a URI object is passed, just return itself.
      return uri if uri.kind_of?(self)
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      # Otherwise, convert to a String
      uri = uri.to_str.dup
      hints = {
        :scheme => "http"
      }.merge(hints)
      case uri
      when /^http:\/+/
        uri.gsub!(/^http:\/+/, "http://")
      when /^feed:\/+http:\/+/
        uri.gsub!(/^feed:\/+http:\/+/, "feed:http://")
      when /^feed:\/+/
        uri.gsub!(/^feed:\/+/, "feed://")
      when /^file:\/+/
        uri.gsub!(/^file:\/+/, "file:///")
      end
      parsed = self.parse(uri)
      if parsed.scheme =~ /^[^\/?#\.]+\.[^\/?#]+$/
        parsed = self.parse(hints[:scheme] + "://" + uri)
      end
      if parsed.authority == nil
        if parsed.path =~ /^[^\/]+\./
          new_host = parsed.path[/^([^\/]+\.[^\/]*)/, 1]
          if new_host
            new_path = parsed.path.gsub(
              Regexp.new("^" + Regexp.escape(new_host)), "")
            parsed.host = new_host
            parsed.path = new_path
            parsed.scheme = hints[:scheme]
          end
        end
      end
      return parsed
    end

    ##
    # Converts a path to a file scheme URI.  If the path supplied is
    # relative, it will be returned as a relative URI.  If the path supplied
    # is actually a non-file URI, it will parse the URI as if it had been
    # parsed with <tt>Addressable::URI.parse</tt>.  Handles all of the
    # various Microsoft-specific formats for specifying paths.
    #
    # @param [String, Addressable::URI, #to_str] path
    #   Typically a <tt>String</tt> path to a file or directory, but
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
    def self.convert_path(path)
      # If we were given nil, return nil.
      return nil unless path
      # If a URI object is passed, just return itself.
      return path if path.kind_of?(self)
      if !path.respond_to?(:to_str)
        raise TypeError, "Can't convert #{path.class} into String."
      end
      # Otherwise, convert to a String
      path = path.to_str.strip

      path.gsub!(/^file:\/?\/?/, "") if path =~ /^file:\/?\/?/
      path = "/" + path if path =~ /^([a-zA-Z])(\||:)/
      uri = self.parse(path)

      if uri.scheme == nil
        # Adjust windows-style uris
        uri.path.gsub!(/^\/?([a-zA-Z])\|(\\|\/)/, "/\\1:/")
        uri.path.gsub!(/\\/, "/")
        if File.exists?(uri.path) &&
            File.stat(uri.path).directory?
          uri.path.gsub!(/\/$/, "")
          uri.path = uri.path + '/'
        end

        # If the path is absolute, set the scheme and host.
        if uri.path =~ /^\//
          uri.scheme = "file"
          uri.host = ""
        end
        uri.normalize!
      end

      return uri
    end

    ##
    # Expands a URI template into a full URI.
    #
    # @param [String, #to_str] pattern The URI template pattern.
    # @param [Hash] mapping The mapping that corresponds to the pattern.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.  The object should
    #   respond to either the <tt>validate</tt> or <tt>transform</tt> messages
    #   or both.  Both the <tt>validate</tt> and <tt>transform</tt> methods
    #   should take two parameters: <tt>name</tt> and <tt>value</tt>.  The
    #   <tt>validate</tt> method should return <tt>true</tt> or
    #   <tt>false</tt>; <tt>true</tt> if the value of the variable is valid,
    #   <tt>false</tt> otherwise.  An <tt>InvalidTemplateValue</tt> exception
    #   will be raised if the value is invalid.  The <tt>transform</tt> method
    #   should return the transformed variable value as a <tt>String</tt>.
    #
    # @return [Addressable::URI] The expanded URI template.
    #
    # @example
    #   class ExampleProcessor
    #     def self.validate(name, value)
    #       return !!(value =~ /^[\w ]+$/) if name == "query"
    #       return true
    #     end
    #
    #     def self.transform(name, value)
    #       return value.gsub(/ /, "+") if name == "query"
    #       return value
    #     end
    #   end
    #
    #   Addressable::URI.expand_template(
    #     "http://example.com/search/{query}/",
    #     {"query" => "an example search query"},
    #     ExampleProcessor
    #   ).to_s
    #   #=> "http://example.com/search/an+example+search+query/"
    #
    #   Addressable::URI.expand_template(
    #     "http://example.com/search/{query}/",
    #     {"query" => "bogus!"},
    #     ExampleProcessor
    #   ).to_s
    #   #=> Addressable::URI::InvalidTemplateValue
    def self.expand_template(pattern, mapping, processor=nil)
      result = pattern.dup
      for name, value in mapping
        transformed_value = value
        if processor != nil
          if processor.respond_to?(:validate)
            if !processor.validate(name, value)
              raise InvalidTemplateValue,
                "(#{name}, #{value}) is an invalid template value."
            end
          end
          if processor.respond_to?(:transform)
            transformed_value = processor.transform(name, value)
          end
        end

        # Handle percent escaping
        transformed_value = self.encode_component(
          transformed_value,
          Addressable::URI::CharacterClasses::RESERVED +
          Addressable::URI::CharacterClasses::UNRESERVED
        )

        result.gsub!(/\{#{Regexp.escape(name)}\}/, transformed_value)
      end
      result.gsub!(
        /\{[#{Addressable::URI::CharacterClasses::UNRESERVED}]+\}/, "")
      return Addressable::URI.parse(result)
    end

    ##
    # Extracts a mapping from the URI using a URI Template pattern.
    #
    # @param [String] pattern
    #   A URI template pattern.
    # @param [#restore, #match] processor
    #   A template processor object may optionally be supplied.
    #   The object should respond to either the <tt>restore</tt> or
    #   <tt>match</tt> messages or both.  The <tt>restore</tt> method should
    #   take two parameters: [String] name and [String] value.  The
    #   <tt>restore</tt> method should reverse any transformations that have
    #   been performed on the value to ensure a valid URI.  The
    #   <tt>match</tt> method should take a single parameter: [String] name.
    #   The <tt>match</tt> method should return a String containing a regular
    #   expression capture group for matching on that particular variable.
    #   The default value is ".*".
    # @return [Hash, NilClass]
    #   The <tt>Hash</tt> mapping that was extracted from the URI, or
    #   <tt>nil</tt> if the URI didn't match the template.
    #
    # @example
    #   class ExampleProcessor
    #     def self.restore(name, value)
    #       return value.gsub(/\+/, " ") if name == "query"
    #       return value
    #     end
    #
    #     def self.match(name)
    #       return ".*?" if name == "first"
    #       return ".*"
    #     end
    #   end
    #
    #   uri = Addressable::URI.parse(
    #     "http://example.com/search/an+example+search+query/"
    #   )
    #   uri.extract_mapping(
    #     "http://example.com/search/{query}/",
    #     ExampleProcessor
    #   )
    #   #=> {"query" => "an example search query"}
    #
    #   uri = Addressable::URI.parse(
    #     "http://example.com/a/b/c/"
    #   )
    #   uri.extract_mapping(
    #     "http://example.com/{first}/{second}/",
    #     ExampleProcessor
    #   )
    #   #=> {"first" => "a", "second" => "b/c"}
    def extract_mapping(pattern, processor=nil)
      mapping = {}
      variable_regexp =
        /\{([#{Addressable::URI::CharacterClasses::UNRESERVED}]+)\}/

      # Get all the variables in the pattern
      variables = pattern.scan(variable_regexp).flatten

      # Initialize all result values to the empty string
      variables.each { |v| mapping[v] = "" }

      # Escape the pattern
      escaped_pattern =
        Regexp.escape(pattern).gsub(/\\\{/, "{").gsub(/\\\}/, "}")

      # Create a regular expression that captures the values of the
      # variables in the URI.
      regexp_string = escaped_pattern.gsub(variable_regexp) do |v|
        capture_group = "(.*)"

        if processor != nil
          if processor.respond_to?(:match)
            name = v[variable_regexp, 1]
            capture_group = "(#{processor.match(name)})"
          end
        end

        capture_group
      end

      # Ensure that the regular expression matches the whole URI.
      regexp_string = "^#{regexp_string}$"

      regexp = Regexp.new(regexp_string)
      values = self.to_s.scan(regexp).flatten

      if variables.size == values.size && variables.size > 0
        # We have a match.
        for i in 0...variables.size
          name = variables[i]
          value = values[i]

          if processor != nil
            if processor.respond_to?(:restore)
              value = processor.restore(name, value)
            end
          end

          mapping[name] = value
        end
        return mapping
      elsif self.to_s == pattern
        # The pattern contained no variables but still matched.
        return mapping
      else
        # Pattern failed to match URI.
        return nil
      end
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
    def self.join(*uris)
      uri_objects = uris.collect do |uri|
        if !uri.respond_to?(:to_str)
          raise TypeError, "Can't convert #{uri.class} into String."
        end
        uri.kind_of?(self) ? uri : self.parse(uri.to_str)
      end
      result = uri_objects.shift.dup
      for uri in uri_objects
        result.merge!(uri)
      end
      return result
    end

    ##
    # Percent encodes a URI component.
    #
    # @param [String, #to_str] component The URI component to encode.
    #
    # @param [String, Regexp] character_class
    #   The characters which are not percent encoded.  If a <tt>String</tt>
    #   is passed, the <tt>String</tt> must be formatted as a regular
    #   expression character class.  (Do not include the surrounding square
    #   brackets.)  For example, <tt>"b-zB-Z0-9"</tt> would cause everything
    #   but the letters 'b' through 'z' and the numbers '0' through '9' to be
    #   percent encoded.  If a <tt>Regexp</tt> is passed, the value
    #   <tt>/[^b-zB-Z0-9]/</tt> would have the same effect.
    #   A set of useful <tt>String</tt> values may be found in the
    #   <tt>Addressable::URI::CharacterClasses</tt> module.  The default value
    #   is the reserved plus unreserved character classes specified in
    #   <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>.
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
    def self.encode_component(component, character_class=
        CharacterClasses::RESERVED + CharacterClasses::UNRESERVED)
      return nil if component.nil?
      if !component.respond_to?(:to_str)
        raise TypeError, "Can't convert #{component.class} into String."
      end
      component = component.to_str
      if ![String, Regexp].include?(character_class.class)
        raise TypeError,
          "Expected String or Regexp, got #{character_class.inspect}"
      end
      if character_class.kind_of?(String)
        character_class = /[^#{character_class}]/
      end
      return component.gsub(character_class) do |sequence|
        (sequence.unpack('C*').map { |c| "%#{c.to_s(16).upcase}" }).join("")
      end
    end

    class << self
      alias_method :encode_component, :encode_component
    end

    ##
    # Unencodes any percent encoded characters within a URI component.
    # This method may be used for unencoding either components or full URIs,
    # however, it is recommended to use the <tt>unencode_component</tt> alias
    # when unencoding components.
    #
    # @param [String, Addressable::URI, #to_str] uri
    #   The URI or component to unencode.
    #
    # @param [Class] returning
    #   The type of object to return.  This value may only be set to
    #   <tt>String</tt> or <tt>Addressable::URI</tt>.  All other values
    #   are invalid.  Defaults to <tt>String</tt>.
    #
    # @return [String, Addressable::URI]
    #   The unencoded component or URI.  The return type is determined by
    #   the <tt>returning</tt> parameter.
    def self.unencode(uri, returning=String)
      return nil if uri.nil?
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      if ![String, ::Addressable::URI].include?(returning)
        raise TypeError,
          "Expected String or Addressable::URI, got #{returning.inspect}"
      end
      result = uri.to_str.gsub(/%[0-9a-f]{2}/i) do |sequence|
        sequence[1..3].to_i(16).chr
      end
      result.force_encoding("utf-8") if result.respond_to?(:force_encoding)
      if returning == String
        return result
      elsif returning == ::Addressable::URI
        return ::Addressable::URI.parse(result)
      end
    end

    class << self
      alias_method :unescape, :unencode
      alias_method :unencode_component, :unencode
      alias_method :unescape_component, :unencode
    end

    ##
    # Percent encodes any special characters in the URI.
    #
    # @param [String, Addressable::URI, #to_str] uri
    #   The URI to encode.
    #
    # @param [Class] returning
    #   The type of object to return.  This value may only be set to
    #   <tt>String</tt> or <tt>Addressable::URI</tt>.  All other values
    #   are invalid.  Defaults to <tt>String</tt>.
    #
    # @return [String, Addressable::URI]
    #   The encoded URI.  The return type is determined by
    #   the <tt>returning</tt> parameter.
    def self.encode(uri, returning=String)
      return nil if uri.nil?
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      if ![String, ::Addressable::URI].include?(returning)
        raise TypeError,
          "Expected String or Addressable::URI, got #{returning.inspect}"
      end
      uri_object = uri.kind_of?(self) ? uri : self.parse(uri.to_str)
      encoded_uri = Addressable::URI.new(
        :scheme => self.encode_component(uri_object.scheme,
          Addressable::URI::CharacterClasses::SCHEME),
        :authority => self.encode_component(uri_object.authority,
          Addressable::URI::CharacterClasses::AUTHORITY),
        :path => self.encode_component(uri_object.path,
          Addressable::URI::CharacterClasses::PATH),
        :query => self.encode_component(uri_object.query,
          Addressable::URI::CharacterClasses::QUERY),
        :fragment => self.encode_component(uri_object.fragment,
          Addressable::URI::CharacterClasses::FRAGMENT)
      )
      if returning == String
        return encoded_uri.to_s
      elsif returning == ::Addressable::URI
        return encoded_uri
      end
    end

    class << self
      alias_method :escape, :encode
    end

    ##
    # Normalizes the encoding of a URI.  Characters within a hostname are
    # not percent encoded to allow for internationalized domain names.
    #
    # @param [String, Addressable::URI, #to_str] uri
    #   The URI to encode.
    #
    # @param [Class] returning
    #   The type of object to return.  This value may only be set to
    #   <tt>String</tt> or <tt>Addressable::URI</tt>.  All other values
    #   are invalid.  Defaults to <tt>String</tt>.
    #
    # @return [String, Addressable::URI]
    #   The encoded URI.  The return type is determined by
    #   the <tt>returning</tt> parameter.
    def self.normalized_encode(uri, returning=String)
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      if ![String, ::Addressable::URI].include?(returning)
        raise TypeError,
          "Expected String or Addressable::URI, got #{returning.inspect}"
      end
      uri_object = uri.kind_of?(self) ? uri : self.parse(uri.to_str)
      components = {
        :scheme => self.unencode_component(uri_object.scheme),
        :user => self.unencode_component(uri_object.user),
        :password => self.unencode_component(uri_object.password),
        :host => self.unencode_component(uri_object.host),
        :port => uri_object.port,
        :path => self.unencode_component(uri_object.path),
        :query => self.unencode_component(uri_object.query),
        :fragment => self.unencode_component(uri_object.fragment)
      }
      components.each do |key, value|
        if value != nil
          components[key] = Addressable::IDNA.unicode_normalize_kc(value.to_s)
        end
      end
      encoded_uri = Addressable::URI.new(
        :scheme => self.encode_component(components[:scheme],
          Addressable::URI::CharacterClasses::SCHEME),
        :user => self.encode_component(components[:user],
          Addressable::URI::CharacterClasses::AUTHORITY),
        :password => self.encode_component(components[:password],
          Addressable::URI::CharacterClasses::AUTHORITY),
        :host => components[:host],
        :port => components[:port],
        :path => self.encode_component(components[:path],
          Addressable::URI::CharacterClasses::PATH),
        :query => self.encode_component(components[:query],
          Addressable::URI::CharacterClasses::QUERY),
        :fragment => self.encode_component(components[:fragment],
          Addressable::URI::CharacterClasses::FRAGMENT)
      )
      if returning == String
        return encoded_uri.to_s
      elsif returning == ::Addressable::URI
        return encoded_uri
      end
    end

    ##
    # Extracts uris from an arbitrary body of text.
    #
    # @param [String, #to_str] text
    #   The body of text to extract URIs from.
    #
    # @option [String, Addressable::URI, #to_str] base
    #   Causes any relative URIs to be resolved against the base URI.
    #
    # @option [TrueClass, FalseClass] parse
    #   If parse is true, all extracted URIs will be parsed.  If parse is
    #   false, the return value with be an <tt>Array</tt> of <tt>Strings</aa>.
    #   Defaults to false.
    #
    # @return [Array] The extracted URIs.
    def self.extract(text, options={})
      defaults = {:base => nil, :parse => false}
      options = defaults.merge(options)
      raise InvalidOptionError unless (options.keys - defaults.keys).empty?
      # This regular expression needs to be less forgiving or else it would
      # match virtually all text.  Which isn't exactly what we're going for.
      extract_regex = /((([a-z\+]+):)[^ \n\<\>\"\\]+[\w\/])/
      extracted_uris =
        text.scan(extract_regex).collect { |match| match[0] }
      sgml_extract_regex = /<[^>]+href=\"([^\"]+?)\"[^>]*>/
      sgml_extracted_uris =
        text.scan(sgml_extract_regex).collect { |match| match[0] }
      extracted_uris.concat(sgml_extracted_uris - extracted_uris)
      textile_extract_regex = /\".+?\":([^ ]+\/[^ ]+)[ \,\.\;\:\?\!\<\>\"]/i
      textile_extracted_uris =
        text.scan(textile_extract_regex).collect { |match| match[0] }
      extracted_uris.concat(textile_extracted_uris - extracted_uris)
      parsed_uris = []
      base_uri = nil
      if options[:base] != nil
        base_uri = options[:base] if options[:base].kind_of?(self)
        base_uri = self.parse(options[:base].to_s) if base_uri == nil
      end
      for uri_string in extracted_uris
        begin
          if base_uri == nil
            parsed_uris << self.parse(uri_string)
          else
            parsed_uris << (base_uri + self.parse(uri_string))
          end
        rescue Exception
          nil
        end
      end
      parsed_uris = parsed_uris.select do |uri|
        (self.ip_based_schemes | [
          "file", "git", "svn", "mailto", "tel"
        ]).include?(uri.normalized_scheme)
      end
      if options[:parse]
        return parsed_uris
      else
        return parsed_uris.collect { |uri| uri.to_s }
      end
    end

    ##
    # Creates a new uri object from component parts.
    #
    # @option [String, #to_str] scheme The scheme component.
    # @option [String, #to_str] user The user component.
    # @option [String, #to_str] password The password component.
    # @option [String, #to_str] userinfo
    #   The userinfo component.  If this is supplied, the user and password
    #   components must be omitted.
    # @option [String, #to_str] host The host component.
    # @option [String, #to_str] port The port component.
    # @option [String, #to_str] authority
    #   The authority component.  If this is supplied, the user, password,
    #   userinfo, host, and port components must be omitted.
    # @option [String, #to_str] path The path component.
    # @option [String, #to_str] query The query component.
    # @option [String, #to_str] fragment The fragment component.
    #
    # @return [Addressable::URI] The constructed URI object.
    def initialize(options={})
      if options[:authority]
        if (options.keys & [:userinfo, :user, :password, :host, :port]).any?
          raise ArgumentError,
            "Cannot specify both an authority and any of the components " +
            "within the authority."
        end
      end
      if options[:userinfo]
        if (options.keys & [:user, :password]).any?
          raise ArgumentError,
            "Cannot specify both a userinfo and either the user or password."
        end
      end

      self.validation_deferred = true
      self.scheme = options[:scheme] if options[:scheme]
      self.user = options[:user] if options[:user]
      self.password = options[:password] if options[:password]
      self.userinfo = options[:userinfo] if options[:userinfo]
      self.host = options[:host] if options[:host]
      self.port = options[:port] if options[:port]
      self.authority = options[:authority] if options[:authority]
      self.path = options[:path] if options[:path]
      self.query = options[:query] if options[:query]
      self.fragment = options[:fragment] if options[:fragment]
      self.validation_deferred = false
    end

    ##
    # The scheme component for this URI.
    #
    # @return [String] The scheme component.
    def scheme
      return @scheme
    end

    ##
    # The scheme component for this URI, normalized.
    #
    # @return [String] The scheme component, normalized.
    def normalized_scheme
      @normalized_scheme ||= (begin
        if self.scheme != nil
          if self.scheme =~ /^\s*ssh\+svn\s*$/i
            "svn+ssh"
          else
            self.scheme.strip.downcase
          end
        else
          nil
        end
      end)
    end

    ##
    # Sets the scheme component for this URI.
    #
    # @param [String, #to_str] new_scheme The new scheme component.
    def scheme=(new_scheme)
      @scheme = new_scheme ? new_scheme.to_str : nil
      @scheme = nil if @scheme.to_s.strip == ""

      # Reset dependant values
      @normalized_scheme = nil
    end

    ##
    # The user component for this URI.
    #
    # @return [String] The user component.
    def user
      return @user
    end

    ##
    # The user component for this URI, normalized.
    #
    # @return [String] The user component, normalized.
    def normalized_user
      @normalized_user ||= (begin
        if self.user
          if normalized_scheme =~ /https?/ && self.user.strip == "" &&
              (!self.password || self.password.strip == "")
            nil
          else
            self.user.strip
          end
        else
          nil
        end
      end)
    end

    ##
    # Sets the user component for this URI.
    #
    # @param [String, #to_str] new_user The new user component.
    def user=(new_user)
      @user = new_user ? new_user.to_str : nil

      # You can't have a nil user with a non-nil password
      if @password != nil
        @user = "" if @user.nil?
      end

      # Reset dependant values
      @userinfo = nil
      @normalized_userinfo = nil
      @authority = nil
      @normalized_user = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns the password for this URI.
    def password
      return @password
    end

    # Returns the URI's password component, normalized.
    def normalized_password
      @normalized_password ||= (begin
        if self.password
          if normalized_scheme =~ /https?/ && self.password.strip == "" &&
              (!self.user || self.user.strip == "")
            nil
          else
            self.password.strip
          end
        else
          nil
        end
      end)
    end

    # Sets the password for this URI.
    def password=(new_password)
      @password = new_password ? new_password.to_str : nil

      # You can't have a nil user with a non-nil password
      if @password != nil
        @user = "" if @user.nil?
      end

      # Reset dependant values
      @userinfo = nil
      @normalized_userinfo = nil
      @authority = nil
      @normalized_password = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns the username and password segment of this URI.
    def userinfo
      @userinfo ||= (begin
        current_user = self.user
        current_password = self.password
        if !current_user && !current_password
          nil
        elsif current_user && current_password
          "#{current_user}:#{current_password}"
        elsif current_user && !current_password
          "#{current_user}"
        end
      end)
    end

    # Returns the URI's userinfo component, normalized.
    def normalized_userinfo
      @normalized_userinfo ||= (begin
        current_user = self.normalized_user
        current_password = self.normalized_password
        if !current_user && !current_password
          nil
        elsif current_user && current_password
          "#{current_user}:#{current_password}"
        elsif current_user && !current_password
          "#{current_user}"
        end
      end)
    end

    # Sets the username and password segment of this URI.
    def userinfo=(new_userinfo)
      new_user, new_password = if new_userinfo
        [
          new_userinfo.to_str.strip[/^(.*):/, 1],
          new_userinfo.to_str.strip[/:(.*)$/, 1]
        ]
      else
        [nil, nil]
      end

      # Password assigned first to ensure validity in case of nil
      self.password = new_password
      self.user = new_user

      # Reset dependant values
      @authority = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns the host for this URI.
    def host
      return @host
    end

    # Returns the URI's host component, normalized.
    def normalized_host
      @normalized_host ||= (begin
        if self.host != nil
          if self.host.strip != ""
            result = ::Addressable::IDNA.to_ascii(
              self.class.unencode_component(self.host.strip.downcase)
            )
            if result[-1..-1] == "."
              # Trailing dots are unnecessary
              result = result[0...-1]
            end
            result
          else
            ""
          end
        else
          nil
        end
      end)
    end

    # Sets the host for this URI.
    def host=(new_host)
      @host = new_host ? new_host.to_str : nil

      # Reset dependant values
      @authority = nil
      @normalized_host = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns the authority segment of this URI.
    def authority
      @authority ||= (begin
        if self.host.nil?
          nil
        else
          authority = ""
          if self.userinfo != nil
            authority << "#{self.userinfo}@"
          end
          authority << self.host
          if self.port != nil
            authority << ":#{self.port}"
          end
          authority
        end
      end)
    end

    # Returns the authority segment of this URI.
    def normalized_authority
      @normalized_authority ||= (begin
        if self.normalized_host.nil?
          nil
        else
          authority = ""
          if self.normalized_userinfo != nil
            authority << "#{self.normalized_userinfo}@"
          end
          authority << self.normalized_host
          if self.normalized_port != nil
            authority << ":#{self.normalized_port}"
          end
          authority
        end
      end)
    end

    # Sets the authority segment of this URI.
    def authority=(new_authority)
      if new_authority
        new_authority = new_authority.to_str
        new_userinfo = new_authority[/^([^\[\]]*)@/, 1]
        if new_userinfo
          new_user = new_userinfo.strip[/^([^:]*):?/, 1]
          new_password = new_userinfo.strip[/:(.*)$/, 1]
        end
        new_host =
          new_authority.gsub(/^([^\[\]]*)@/, "").gsub(/:([^:@\[\]]*?)$/, "")
        new_port =
          new_authority[/:([^:@\[\]]*?)$/, 1]
      end

      # Password assigned first to ensure validity in case of nil
      self.password = new_password
      self.user = new_user
      self.host = new_host
      self.port = new_port

      # Reset dependant values
      @inferred_port = nil
      @userinfo = nil
      @normalized_userinfo = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns an array of known ip-based schemes.  These schemes typically
    # use a similar URI form:
    # //<user>:<password>@<host>:<port>/<url-path>
    def self.ip_based_schemes
      return self.port_mapping.keys
    end

    # Returns a hash of common IP-based schemes and their default port
    # numbers.  Adding new schemes to this hash, as necessary, will allow
    # for better URI normalization.
    def self.port_mapping
      @port_mapping ||= {
        "http" => 80,
        "https" => 443,
        "ftp" => 21,
        "tftp" => 69,
        "sftp" => 22,
        "ssh" => 22,
        "svn+ssh" => 22,
        "telnet" => 23,
        "nntp" => 119,
        "gopher" => 70,
        "wais" => 210,
        "ldap" => 389,
        "prospero" => 1525
      }
    end

    # Returns the port number that was actually specified in the URI string.
    def port
      return @port
    end

    # Returns the URI's port component, normalized.
    def normalized_port
      @normalized_port ||= (begin
        if self.class.port_mapping[normalized_scheme] == self.port
          nil
        else
          self.port
        end
      end)
    end

    # Sets the port for this URI.
    def port=(new_port)
      if new_port != nil && !(new_port.to_s =~ /^\d+$/)
        raise InvalidURIError,
          "Invalid port number: #{new_port.inspect}"
      end

      @port = new_port.to_s.to_i
      @port = nil if @port == 0

      # Reset dependant values
      @authority = nil
      @inferred_port = nil
      @normalized_port = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    # Returns the port number for this URI.  This method will normalize to the
    # default port for the URI's scheme if the port isn't explicitly specified
    # in the URI.
    def inferred_port
      @inferred_port ||= (begin
        if port.to_i == 0
          if scheme
            self.class.port_mapping[scheme.strip.downcase]
          else
            nil
          end
        else
          port.to_i
        end
      end)
    end

    # Returns the path for this URI.
    def path
      return (@path || "")
    end

    # Returns the URI's path component, normalized.
    def normalized_path
      @normalized_path ||= (begin
        result = self.class.normalize_path(self.path.strip)
        if result == "" &&
            ["http", "https", "ftp", "tftp"].include?(self.normalized_scheme)
          result = "/"
        end
        result
      end)
    end

    # Sets the path for this URI.
    def path=(new_path)
      @path = (new_path || "").to_str
      if @path != "" && @path[0..0] != "/" && host != nil
        @path = "/#{@path}"
      end

      # Reset dependant values
      @normalized_path = nil
    end

    # Returns the basename, if any, of the file at the path being referenced.
    # Returns nil if there is no path component.
    def basename
      # Path cannot be nil
      return File.basename(self.path).gsub(/;[^\/]*$/, "")
    end

    # Returns the extension, if any, of the file at the path being referenced.
    # Returns "" if there is no extension or nil if there is no path
    # component.
    def extname
      return nil unless self.path
      return File.extname(self.basename)
    end

    # Returns the query string for this URI.
    def query
      return @query
    end

    # Returns the URI's query component, normalized.
    def normalized_query
      @normalized_query ||= (self.query ? self.query.strip : nil)
    end

    # Sets the query string for this URI.
    def query=(new_query)
      @query = new_query.to_str

      # Reset dependant values
      @normalized_query = nil
    end

    ##
    # Converts the query component to a Hash value.
    #
    # @option options :notation [Symbol] (:subscript)
    #   May be one of <tt>:flat</tt>, <tt>:dot</tt>, or <tt>:subscript</tt>.
    #   The <tt>:dot</tt> notation is not supported for assignment.
    #
    # @return [Hash] The query string parsed as a Hash object.
    #
    # @example
    #   Addressable::URI.parse("?one=1&two=2&three=3").query_values
    #   #=> {"one" => "1", "two" => "2", "three" => "3"}
    #   Addressable::URI.parse("?one[two][three]=four").query_values
    #   #=> {"one" => {"two" => {"three" => "four"}}}
    #   Addressable::URI.parse("?one.two.three=four").query_values(
    #     :notation => :dot
    #   )
    #   #=> {"one" => {"two" => {"three" => "four"}}}
    #   Addressable::URI.parse("?one[two][three]=four").query_values(
    #     :notation => :flat
    #   )
    #   #=> {"one[two][three]" => "four"}
    #   Addressable::URI.parse("?one.two.three=four").query_values(
    #     :notation => :flat
    #   )
    #   #=> {"one.two.three" => "four"}
    #   Addressable::URI.parse(
    #     "?one[two][three][]=four&one[two][three][]=five"
    #   ).query_values
    #   #=> {"one" => {"two" => {"three" => ["four", "five"]}}}
    def query_values(options={})
      defaults = {:notation => :subscript}
      options = defaults.merge(options)
      if ![:flat, :dot, :subscript].include?(options[:notation])
        raise ArgumentError,
          "Invalid notation. Must be one of: [:flat, :dot, :subscript]."
      end
      return nil if self.query == nil
      return (self.query.split("&").map do |pair|
        pair.split("=")
      end).inject({}) do |accumulator, pair|
        key, value = pair
        value = true if value.nil?
        key = self.class.unencode_component(key)
        if value != true
          value = self.class.unencode_component(value).gsub(/\+/, " ")
        end
        if options[:notation] == :flat
          if accumulator[key]
            raise ArgumentError, "Key was repeated: #{key.inspect}"
          end
          accumulator[key] = value
        else
          if options[:notation] == :dot
            array_value = false
            subkeys = key.split(".")
          elsif options[:notation] == :subscript
            array_value = !!(key =~ /\[\]$/)
            subkeys = key.split(/[\[\]]+/)
          end
          current_hash = accumulator
          for i in 0...(subkeys.size - 1)
            subkey = subkeys[i]
            current_hash[subkey] = {} unless current_hash[subkey]
            current_hash = current_hash[subkey]
          end
          if array_value
            current_hash[subkeys.last] = [] unless current_hash[subkeys.last]
            current_hash[subkeys.last] << value
          else
            current_hash[subkeys.last] = value
          end
        end
        accumulator
      end
    end

    # Sets the query string for this URI from a Hash object.
    def query_values=(new_query_hash)
      @query = (new_query_hash.inject([]) do |accumulator, pair|
        key, value = pair
        key = self.class.encode_component(key, CharacterClasses::UNRESERVED)
        if value == true
          accumulator << "#{key}"
        else
          value = self.class.encode_component(
            value, CharacterClasses::UNRESERVED)
          accumulator << "#{key}=#{value}"
        end
      end).join("&")

      # Reset dependant values
      @normalized_query = nil
    end

    # Returns the fragment for this URI.
    def fragment
      return @fragment
    end

    # Returns the URI's fragment component, normalized.
    def normalized_fragment
      @normalized_fragment ||= (self.fragment ? self.fragment.strip : nil)
    end

    # Sets the fragment for this URI.
    def fragment=(new_fragment)
      @fragment = new_fragment.to_str

      # Reset dependant values
      @normalized_fragment = nil
    end

    # Returns true if the URI uses an IP-based protocol.
    def ip_based?
      if self.scheme
        return self.class.ip_based_schemes.include?(
          self.scheme.strip.downcase)
      end
      return false
    end

    # Returns true if this URI is known to be relative.
    def relative?
      return self.scheme.nil?
    end

    # Returns true if this URI is known to be absolute.
    def absolute?
      return !relative?
    end

    # Joins two URIs together.
    def +(uri)
      if !uri.respond_to?(:to_str)
        raise TypeError, "Can't convert #{uri.class} into String."
      end
      if !uri.kind_of?(self.class)
        # Otherwise, convert to a String, then parse.
        uri = self.class.parse(uri.to_str)
      end
      if uri.to_s == ""
        return self.dup
      end

      joined_scheme = nil
      joined_user = nil
      joined_password = nil
      joined_host = nil
      joined_port = nil
      joined_path = nil
      joined_query = nil
      joined_fragment = nil

      # Section 5.2.2 of RFC 3986
      if uri.scheme != nil
        joined_scheme = uri.scheme
        joined_user = uri.user
        joined_password = uri.password
        joined_host = uri.host
        joined_port = uri.port
        joined_path = self.class.normalize_path(uri.path)
        joined_query = uri.query
      else
        if uri.authority != nil
          joined_user = uri.user
          joined_password = uri.password
          joined_host = uri.host
          joined_port = uri.port
          joined_path = self.class.normalize_path(uri.path)
          joined_query = uri.query
        else
          if uri.path == nil || uri.path == ""
            joined_path = self.path
            if uri.query != nil
              joined_query = uri.query
            else
              joined_query = self.query
            end
          else
            if uri.path[0..0] == "/"
              joined_path = self.class.normalize_path(uri.path)
            else
              base_path = self.path.dup
              base_path = "" if base_path == nil
              base_path = self.class.normalize_path(base_path)

              # Section 5.2.3 of RFC 3986
              #
              # Removes the right-most path segment from the base path.
              if base_path =~ /\//
                base_path.gsub!(/\/[^\/]+$/, "/")
              else
                base_path = ""
              end

              # If the base path is empty and an authority segment has been
              # defined, use a base path of "/"
              if base_path == "" && self.authority != nil
                base_path = "/"
              end

              joined_path = self.class.normalize_path(base_path + uri.path)
            end
            joined_query = uri.query
          end
          joined_user = self.user
          joined_password = self.password
          joined_host = self.host
          joined_port = self.port
        end
        joined_scheme = self.scheme
      end
      joined_fragment = uri.fragment

      return Addressable::URI.new(
        :scheme => joined_scheme,
        :user => joined_user,
        :password => joined_password,
        :host => joined_host,
        :port => joined_port,
        :path => joined_path,
        :query => joined_query,
        :fragment => joined_fragment
      )
    end

    # Merges two URIs together.
    def merge(uri)
      return self + uri
    end
    alias_method :join, :merge

    # Destructive form of merge.
    def merge!(uri)
      replace_self(self.merge(uri))
    end
    alias_method :join!, :merge!

    # Returns the shortest normalized relative form of this URI that uses the
    # supplied URI as a base for resolution.  Returns an absolute URI if
    # necessary.
    def route_from(uri)
      uri = self.class.parse(uri).normalize
      normalized_self = self.normalize
      if normalized_self.relative?
        raise ArgumentError, "Expected absolute URI, got: #{self.to_s}"
      end
      if uri.relative?
        raise ArgumentError, "Expected absolute URI, got: #{uri.to_s}"
      end
      if normalized_self == uri
        return Addressable::URI.parse("##{normalized_self.fragment}")
      end
      components = normalized_self.to_hash
      if normalized_self.scheme == uri.scheme
        components[:scheme] = nil
        if normalized_self.authority == uri.authority
          components[:user] = nil
          components[:password] = nil
          components[:host] = nil
          components[:port] = nil
          if normalized_self.path == uri.path
            components[:path] = nil
            if normalized_self.query == uri.query
              components[:query] = nil
            end
          else
            if uri.path != "/"
              components[:path].gsub!(
                Regexp.new("^" + Regexp.escape(uri.path)), "")
            end
          end
        end
      end
      # Avoid network-path references.
      if components[:host] != nil
        components[:scheme] = normalized_self.scheme
      end
      return Addressable::URI.new(
        :scheme => components[:scheme],
        :user => components[:user],
        :password => components[:password],
        :host => components[:host],
        :port => components[:port],
        :path => components[:path],
        :query => components[:query],
        :fragment => components[:fragment]
      )
    end

    # Returns the shortest normalized relative form of the supplied URI that
    # uses this URI as a base for resolution.  Returns an absolute URI if
    # necessary.
    def route_to(uri)
      return self.class.parse(uri).route_from(self)
    end

    # Returns a normalized URI object.
    #
    # NOTE: This method does not attempt to fully conform to specifications.
    # It exists largely to correct other people's failures to read the
    # specifications, and also to deal with caching issues since several
    # different URIs may represent the same resource and should not be
    # cached multiple times.
    def normalize
      # This is a special exception for the frequently misused feed
      # URI scheme.
      if normalized_scheme == "feed"
        if self.to_s =~ /^feed:\/*http:\/*/
          return self.class.parse(
            self.to_s[/^feed:\/*(http:\/*.*)/, 1]
          ).normalize
        end
      end

      return Addressable::URI.normalized_encode(
        Addressable::URI.new(
          :scheme => normalized_scheme,
          :authority => normalized_authority,
          :path => normalized_path,
          :query => normalized_query,
          :fragment => normalized_fragment
        ),
        ::Addressable::URI
      )
    end

    # Destructively normalizes this URI object.
    def normalize!
      replace_self(self.normalize)
    end

    # Creates a URI suitable for display to users.  If semantic attacks are
    # likely, the application should try to detect these and warn the user.
    # See <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>,
    # section 7.6 for more information.
    def display_uri
      display_uri = self.normalize
      display_uri.instance_variable_set("@host",
        ::Addressable::IDNA.to_unicode(display_uri.host))
      return display_uri
    end

    # Returns true if the URI objects are equal.  This method normalizes
    # both URIs before doing the comparison, and allows comparison against
    # strings.
    def ===(uri)
      if uri.respond_to?(:normalize)
        uri_string = uri.normalize.to_s
      else
        begin
          uri_string = URI.parse(uri.to_s).normalize.to_s
        rescue InvalidURIError
          return false
        end
      end
      return self.normalize.to_s == uri_string
    end

    # Returns true if the URI objects are equal.  This method normalizes
    # both URIs before doing the comparison.
    def ==(uri)
      return false unless uri.kind_of?(self.class)
      return self.normalize.to_s == uri.normalize.to_s
    end

    # Returns true if the URI objects are equal.  This method does NOT
    # normalize either URI before doing the comparison.
    def eql?(uri)
      return false unless uri.kind_of?(self.class)
      return self.to_s == uri.to_s
    end

    # Returns a hash value that will make a URI equivalent to its normalized
    # form.
    def hash
      return (self.normalize.to_s.hash * -1)
    end

    # Clones the URI object.
    def dup
      duplicated_uri = Addressable::URI.new(
        :scheme => self.scheme ? self.scheme.dup : nil,
        :user => self.user ? self.user.dup : nil,
        :password => self.password ? self.password.dup : nil,
        :host => self.host ? self.host.dup : nil,
        :port => self.port,
        :path => self.path ? self.path.dup : nil,
        :query => self.query ? self.query.dup : nil,
        :fragment => self.fragment ? self.fragment.dup : nil
      )
      return duplicated_uri
    end

    ##
    # Omits components from a URI.
    #
    # @param [Symbol] *components The components to be omitted.
    #
    # @return [Addressable::URI] The URI with components omitted.
    #
    # @example
    #   uri = Addressable::URI.parse("http://example.com/path?query")
    #   #=> #<Addressable::URI:0xcc5e7a URI:http://example.com/path?query>
    #   uri.omit(:scheme, :authority)
    #   #=> #<Addressable::URI:0xcc4d86 URI:/path?query>
    def omit(*components)
      invalid_components = components - [
        :scheme, :user, :password, :userinfo, :host, :port, :authority,
        :path, :query, :fragment
      ]
      unless invalid_components.empty?
        raise ArgumentError,
          "Invalid component names: #{invalid_components.inspect}."
      end
      duplicated_uri = self.dup
      duplicated_uri.validation_deferred = true
      components.each do |component|
        duplicated_uri.send((component.to_s + "=").to_sym, nil)
      end
      duplicated_uri.validation_deferred = false
      duplicated_uri
    end

    ##
    # Destructive form of omit.
    #
    # @see Addressable::URI#omit
    def omit!(*components)
      replace_self(self.omit(*components))
    end

    # Returns the assembled URI as a string.
    def to_s
      uri_string = ""
      uri_string << "#{self.scheme}:" if self.scheme != nil
      uri_string << "//#{self.authority}" if self.authority != nil
      uri_string << self.path.to_s
      uri_string << "?#{self.query}" if self.query != nil
      uri_string << "##{self.fragment}" if self.fragment != nil
      if uri_string.respond_to?(:force_encoding)
        uri_string.force_encoding(Encoding::UTF_8)
      end
      return uri_string
    end

    # URI's are glorified Strings.  Allow implicit conversion.
    alias_method :to_str, :to_s

    # Returns a Hash of the URI components.
    def to_hash
      return {
        :scheme => self.scheme,
        :user => self.user,
        :password => self.password,
        :host => self.host,
        :port => self.port,
        :path => self.path,
        :query => self.query,
        :fragment => self.fragment
      }
    end

    # Returns a string representation of the URI object's state.
    def inspect
      sprintf("#<%s:%#0x URI:%s>", self.class.to_s, self.object_id, self.to_s)
    end

    ##
    # If URI validation needs to be disabled, this can be set to true.
    def validation_deferred
      @validation_deferred ||= false
    end

    ##
    # If URI validation needs to be disabled, this can be set to true.
    def validation_deferred=(new_validation_deferred)
      @validation_deferred = new_validation_deferred
      validate unless @validation_deferred
    end

  private
    # Resolves paths to their simplest form.
    def self.normalize_path(path)
      # Section 5.2.4 of RFC 3986

      return nil if path.nil?
      normalized_path = path.dup
      previous_state = normalized_path.dup
      begin
        previous_state = normalized_path.dup
        normalized_path.gsub!(/\/\.\//, "/")
        normalized_path.gsub!(/\/\.$/, "/")
        parent = normalized_path[/\/([^\/]+)\/\.\.\//, 1]
        if parent != "." && parent != ".."
          normalized_path.gsub!(/\/#{parent}\/\.\.\//, "/")
        end
        parent = normalized_path[/\/([^\/]+)\/\.\.$/, 1]
        if parent != "." && parent != ".."
          normalized_path.gsub!(/\/#{parent}\/\.\.$/, "/")
        end
        normalized_path.gsub!(/^\.\.?\/?/, "")
        normalized_path.gsub!(/^\/\.\.?\//, "/")
      end until previous_state == normalized_path
      return normalized_path
    end

    ##
    # Ensures that the URI is valid.
    def validate
      return if self.validation_deferred
      if self.scheme != nil &&
          (self.host == nil || self.host == "") &&
          (self.path == nil || self.path == "")
        raise InvalidURIError,
          "Absolute URI missing hierarchical segment: '#{self.to_s}'"
      end
      if self.host == nil
        if self.port != nil ||
            self.user != nil ||
            self.password != nil
          raise InvalidURIError, "Hostname not supplied: '#{self.to_s}'"
        end
      end
      return nil
    end

    # Replaces the internal state of self with the specified URI's state.
    # Used in destructive operations to avoid massive code repetition.
    def replace_self(uri)
      # Reset dependant values
      instance_variables.each do |var|
        instance_variable_set(var, nil)
      end

      @scheme = uri.scheme
      @user = uri.user
      @password = uri.password
      @host = uri.host
      @port = uri.port
      @path = uri.path
      @query = uri.query
      @fragment = uri.fragment
      return self
    end
  end
end
