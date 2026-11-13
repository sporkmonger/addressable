# frozen_string_literal: true

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


require "strscan"
require "addressable/version"
require "addressable/uri"

module Addressable
  ##
  # This is an implementation of a URI template based on
  # RFC 6570 (http://tools.ietf.org/html/rfc6570).
  class Template
    # Constants used throughout the template code.
    anything =
      Addressable::URI::CharacterClasses::RESERVED +
      Addressable::URI::CharacterClasses::UNRESERVED


    variable_char_class =
      Addressable::URI::CharacterClasses::ALPHA +
      Addressable::URI::CharacterClasses::DIGIT + '_'

    var_char =
      "(?>(?:[#{variable_char_class}]|%[a-fA-F0-9][a-fA-F0-9])+)"
    # Matching accepts a non-ASCII character as it is or pct-encoded.
    non_ascii = "[^\\x00-\\x7F]"
    RESERVED =
      "(?:[#{anything}]|#{non_ascii}|%[a-fA-F0-9][a-fA-F0-9])"
    RESERVED_NO_COMMA =
      "(?:[#{anything.delete(',')}]|#{non_ascii}|%[a-fA-F0-9][a-fA-F0-9])"
    UNRESERVED =
      "(?:[#{
        Addressable::URI::CharacterClasses::UNRESERVED
      }]|#{non_ascii}|%[a-fA-F0-9][a-fA-F0-9])"
    # Reserved and fragment expansion encode every character outside the
    # reserved and unreserved sets, except a "%" that starts a pct-encoded
    # triplet (RFC 6570 section 3.2.3).
    RESERVED_ENCODE = /%(?![0-9A-Fa-f]{2})|[^%#{anything}]/
    PCT_ENCODED_OR_CHARACTER = /%[0-9A-Fa-f]{2}|./m
    HEX_DIGITS = "0123456789ABCDEFabcdef".bytes.freeze
    # Whether a regular expression group name can start with ".". Ruby 2.3
    # and earlier only allow a letter or "_" as its first character.
    GROUP_NAME_CAN_START_WITH_DOT = begin
      Regexp.new("(?<.a>)")
      true
    rescue RegexpError
      false
    end
    # A "#" after the one that starts a fragment, as written or as expansion
    # encodes it.
    NUMBER_SIGN_EITHER_FORM = "(?:\\#|%23)"
    # A literal's token: a run of non-ASCII pct-encoded octets, one triplet, or
    # one character.
    LITERAL_TOKEN = /(?:%[89A-Fa-f][0-9A-Fa-f])+|%[0-9A-Fa-f]{2}|./m
    variable =
      "(?:#{var_char}(?:\\.?#{var_char})*)"
    varspec =
      "(?:(#{variable})(\\*|:[1-9]\\d{0,3})?)"
    VARNAME =
      /^#{variable}$/
    VARSPEC =
      /^#{varspec}$/
    VARIABLE_LIST =
      /^#{varspec}(?:,#{varspec})*$/
    operator =
      "+#./;?&=,!@|"
    EXPRESSION =
      /\{([#{operator}])?(#{varspec}(?:,#{varspec})*)\}/
    # RFC 6570 reserves these operators for future extensions.
    RESERVED_OPERATORS = "=,!@|"
    VALID_EXPRESSION =
      /\A\{[+#.\/;?&]?#{varspec}(?:,#{varspec})*\}\z/
    # Literal text, an expression up to the next "}" (or the end, if there's
    # no "}"), or a "}" that doesn't close an expression.
    TEMPLATE_TOKEN = /[^{}]+|\{[^}]*\}?|\}/
    # Expansion encodes non-ASCII literals (RFC 6570 section 3.1). An ASCII
    # character the literals grammar leaves out stays as it is, as most other
    # implementations do.
    LITERAL_ENCODE = /[^\x00-\x7F]/
    # Characters that label expansion encodes, so a value can't contain them
    # as they are: the reserved set (RFC 3986 section 2.2).
    LABEL_DELIMITER = /[:\/?#\[\]@!$&'()*+,;=]/
    private_constant :RESERVED_OPERATORS, :VALID_EXPRESSION, :TEMPLATE_TOKEN,
      :LITERAL_ENCODE, :NUMBER_SIGN_EITHER_FORM, :LITERAL_TOKEN,
      :GROUP_NAME_CAN_START_WITH_DOT, :HEX_DIGITS, :LABEL_DELIMITER

    NO_MAPPING = Object.new.freeze
    private_constant :NO_MAPPING

    # Looks up variables in a mapping that isn't enumerable, such as a lambda,
    # once each. As with Hash#fetch, a KeyError means the variable is missing,
    # and nil means it's defined as nil.
    class MappingLookup
      MISSING = Object.new.freeze

      def initialize(source)
        @source = source
        @values = {}
      end

      def [](name)
        value = lookup(name)
        value.equal?(MISSING) ? nil : value
      end

      def key?(name)
        !lookup(name).equal?(MISSING)
      end

      private

      def lookup(name)
        @values.fetch(name) do
          @values[name] =
            if @source.respond_to?(:key?) && !@source.key?(name)
              MISSING
            else
              begin
                @source[name]
              rescue KeyError => error
                raise unless missing?(error, name)
                MISSING
              end
            end
        end
      end

      # KeyError#key is Ruby 2.6+. For an error with no key, MRI raises and
      # TruffleRuby gives nil.
      def missing?(error, name)
        return true unless error.respond_to?(:key)
        begin
          key = error.key
        rescue ArgumentError
          return true
        end
        return true if key.nil?
        (key.is_a?(String) || key.is_a?(Symbol)) && key.to_s == name
      end
    end
    private_constant :MappingLookup


    LEADERS = {
      '?' => '?',
      '/' => '/',
      '#' => '#',
      '.' => '.',
      ';' => ';',
      '&' => '&'
    }
    JOINERS = {
      '?' => '&',
      '.' => '.',
      ';' => ';',
      '&' => '&',
      '/' => '/'
    }

    ##
    # Raised if an invalid template value is supplied.
    class InvalidTemplateValueError < StandardError
    end

    ##
    # Raised if a template that doesn't match the RFC 6570 grammar is
    # expanded.
    class InvalidTemplateError < StandardError
    end

    ##
    # Raised if an invalid template operator is used in a pattern.
    class InvalidTemplateOperatorError < InvalidTemplateError
    end

    ##
    # Raised if an invalid template operator is used in a pattern.
    class TemplateOperatorAbortedError < StandardError
    end

    ##
    # This class represents the data that is extracted when a Template
    # is matched against a URI.
    class MatchData
      ##
      # Creates a new MatchData object.
      # MatchData objects should never be instantiated directly.
      #
      # @param [Addressable::URI] uri
      #   The URI that the template was matched against.
      def initialize(uri, template, mapping)
        @uri = uri.dup.freeze
        @template = template
        @mapping = mapping.dup.freeze
      end

      ##
      # @return [Addressable::URI]
      #   The URI that the Template was matched against.
      attr_reader :uri

      ##
      # @return [Addressable::Template]
      #   The Template used for the match.
      attr_reader :template

      ##
      # @return [Hash]
      #   The mapping that resulted from the match.
      #   Note that this mapping does not include keys or values for
      #   variables that appear in the Template, but are not present
      #   in the URI.
      attr_reader :mapping

      ##
      # @return [Array]
      #   The list of variables that were present in the Template.
      #   Note that this list will include variables which do not appear
      #   in the mapping because they were not present in URI.
      def variables
        self.template.variables
      end
      alias_method :keys, :variables
      alias_method :names, :variables

      ##
      # @return [Array]
      #   The list of values that were captured by the Template.
      #   Note that this list will include nils for any variables which
      #   were in the Template, but did not appear in the URI.
      def values
        (@values ||= self.variables.inject([]) do |accu, key|
          accu << self.mapping[key]
          accu
        end).dup
      end
      alias_method :captures, :values

      ##
      # Accesses captured values by name or by index.
      #
      # @param [String, Symbol, Fixnum] key
      #   Capture index or name. Note that when accessing by with index
      #   of 0, the full URI will be returned. The intention is to mimic
      #   the ::MatchData#[] behavior.
      #
      # @param [#to_int, nil] len
      #   If provided, an array of values will be returned with the given
      #   parameter used as length.
      #
      # @return [Array, String, nil]
      #   The captured value corresponding to the index or name. If the
      #   value was not provided or the key is unknown, nil will be
      #   returned.
      #
      #   If the second parameter is provided, an array of that length will
      #   be returned instead.
      def [](key, len = nil)
        if len
          to_a[key, len]
        elsif String === key or Symbol === key
          mapping[key.to_s]
        else
          to_a[key]
        end
      end

      ##
      # @return [Array]
      #   Array with the matched URI as first element followed by the captured
      #   values.
      def to_a
        [to_s, *values]
      end

      ##
      # @return [String]
      #   The matched URI as String.
      def to_s
        uri.to_s
      end
      alias_method :string, :to_s

      # Returns multiple captured values at once.
      #
      # @param [String, Symbol, Fixnum] *indexes
      #   Indices of the captures to be returned
      #
      # @return [Array]
      #   Values corresponding to given indices.
      #
      # @see Addressable::Template::MatchData#[]
      def values_at(*indexes)
        indexes.map { |i| self[i] }
      end

      ##
      # Returns a <tt>String</tt> representation of the MatchData's state.
      #
      # @return [String] The MatchData's state, as a <tt>String</tt>.
      def inspect
        sprintf("#<%s:%#0x RESULT:%s>",
          self.class.to_s, self.object_id, self.mapping.inspect)
      end

      ##
      # Dummy method for code expecting a ::MatchData instance
      #
      # @return [String] An empty string.
      def pre_match
        ""
      end
      alias_method :post_match, :pre_match
    end

    ##
    # Creates a new <tt>Addressable::Template</tt> object.
    #
    # @param [#to_str] pattern The URI Template pattern.
    #
    # @return [Addressable::Template] The initialized Template object.
    def initialize(pattern)
      if !pattern.respond_to?(:to_str)
        raise TypeError, "Can't convert #{pattern.class} into String."
      end
      @pattern = pattern.to_str.dup.freeze
    end

    ##
    # Freeze URI, initializing instance variables.
    #
    # @return [Addressable::URI] The frozen URI object.
    def freeze
      self.variables
      self.variable_defaults
      parse_template_pattern(pattern)
      super
    end

    ##
    # @return [String] The Template object's pattern.
    attr_reader :pattern

    ##
    # Returns a <tt>String</tt> representation of the Template object's state.
    #
    # @return [String] The Template object's state, as a <tt>String</tt>.
    def inspect
      sprintf("#<%s:%#0x PATTERN:%s>",
        self.class.to_s, self.object_id, self.pattern)
    end

    ##
    # Returns <code>true</code> if the Template objects are equal. This method
    # does NOT normalize either Template before doing the comparison.
    #
    # @param [Object] template The Template to compare.
    #
    # @return [TrueClass, FalseClass]
    #   <code>true</code> if the Templates are equivalent, <code>false</code>
    #   otherwise.
    def ==(template)
      return false unless template.kind_of?(Template)
      return self.pattern == template.pattern
    end

    ##
    # Addressable::Template makes no distinction between `==` and `eql?`.
    #
    # @see #==
    alias_method :eql?, :==

    ##
    # @return [Integer] A hash consistent with template equality.
    def hash
      self.pattern.hash
    end

    ##
    # Extracts a mapping from the URI using a URI Template pattern.
    #
    # @param [Addressable::URI, #to_str] uri
    #   The URI to extract from.
    #
    # @param [#restore, #match] processor
    #   A template processor object may optionally be supplied.
    #
    #   The object should respond to either the <tt>restore</tt> or
    #   <tt>match</tt> messages or both. The <tt>restore</tt> method should
    #   take two parameters: `[String] name` and `[String] value`.
    #   The <tt>restore</tt> method should reverse any transformations that
    #   have been performed on the value to ensure a valid URI.
    #   The <tt>match</tt> method should take a single
    #   parameter: `[String] name`.  The <tt>match</tt> method should return
    #   a <tt>String</tt> containing a regular expression capture group for
    #   matching on that particular variable. The default value is `".*?"`.
    #   The <tt>match</tt> method has no effect on multivariate operator
    #   expansions.
    #
    # Without a processor, each value is pct-decoded once. Reserved
    # (<tt>{+var}</tt>) and fragment (<tt>{#var}</tt>) expansion keep a
    # value's pct-encoded triplets (RFC 6570 section 3.2.3), so for those
    # operators, expanding an extracted value can give a different URI:
    # <tt>{+path}</tt> extracts <tt>a/b</tt> from <tt>a%2Fb</tt>, which
    # expands to <tt>a/b</tt>, and a value pct-encoded twice comes back
    # encoded once. With any processor, even one that only responds to
    # <tt>match</tt>, values aren't decoded: each is given as it appears in
    # the URI, after <tt>restore</tt> if the processor has it.
    #
    # An exploded <tt>;</tt>, <tt>?</tt> or <tt>&</tt> value whose pairs all
    # have the variable's name as their key is a list; other pairs are an
    # associative array. The key is compared with the name as written, so
    # <tt>{?a*}</tt> reads <tt>?%61=x</tt> as the pair <tt>%61</tt>, decoded
    # to <tt>a</tt>, not as a list.
    #
    # Label expansion (<tt>{.var}</tt>) leaves a <tt>.</tt> in a value as it
    # is, so a value can only contain <tt>.</tt> where it's clear where it
    # ends: a label expression with one variable that isn't exploded, set off
    # on both sides by the start or end of the URI or by characters that
    # label expansion encodes, such as <tt>/</tt>, <tt>?</tt> or <tt>;</tt>.
    # <tt>/f{.ext}</tt> extracts <tt>tar.gz</tt> from <tt>/f.tar.gz</tt>.
    # Elsewhere, each <tt>.</tt> starts a label: <tt>/{name}{.ext}</tt> reads
    # <tt>/archive.tar.gz</tt> as <tt>archive.tar</tt> and <tt>gz</tt>.
    #
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    #
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
    #   Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).extract(uri, ExampleProcessor)
    #   #=> {"query" => "an example search query"}
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   Addressable::Template.new(
    #     "http://example.com/{first}/{second}/"
    #   ).extract(uri, ExampleProcessor)
    #   #=> {"first" => "a", "second" => "b/c"}
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   Addressable::Template.new(
    #     "http://example.com/{first}/{-list|/|second}/"
    #   ).extract(uri)
    #   #=> {"first" => "a", "second" => ["b", "c"]}
    def extract(uri, processor=nil)
      match_data = self.match(uri, processor)
      return (match_data ? match_data.mapping : nil)
    end

    ##
    # Extracts match data from the URI using a URI Template pattern.
    #
    # @param [Addressable::URI, #to_str] uri
    #   The URI to extract from.
    #
    # @param [#restore, #match] processor
    #   A template processor object may optionally be supplied.
    #
    #   The object should respond to either the <tt>restore</tt> or
    #   <tt>match</tt> messages or both. The <tt>restore</tt> method should
    #   take two parameters: `[String] name` and `[String] value`.
    #   The <tt>restore</tt> method should reverse any transformations that
    #   have been performed on the value to ensure a valid URI.
    #   The <tt>match</tt> method should take a single
    #   parameter: `[String] name`. The <tt>match</tt> method should return
    #   a <tt>String</tt> containing a regular expression capture group for
    #   matching on that particular variable. The default value is `".*?"`.
    #   The <tt>match</tt> method has no effect on multivariate operator
    #   expansions.
    #
    # Without a processor, each value is pct-decoded once. Reserved
    # (<tt>{+var}</tt>) and fragment (<tt>{#var}</tt>) expansion keep a
    # value's pct-encoded triplets (RFC 6570 section 3.2.3), so for those
    # operators, expanding an extracted value can give a different URI:
    # <tt>{+path}</tt> extracts <tt>a/b</tt> from <tt>a%2Fb</tt>, which
    # expands to <tt>a/b</tt>, and a value pct-encoded twice comes back
    # encoded once. With any processor, even one that only responds to
    # <tt>match</tt>, values aren't decoded: each is given as it appears in
    # the URI, after <tt>restore</tt> if the processor has it.
    #
    # An exploded <tt>;</tt>, <tt>?</tt> or <tt>&</tt> value whose pairs all
    # have the variable's name as their key is a list; other pairs are an
    # associative array. The key is compared with the name as written, so
    # <tt>{?a*}</tt> reads <tt>?%61=x</tt> as the pair <tt>%61</tt>, decoded
    # to <tt>a</tt>, not as a list.
    #
    # Label expansion (<tt>{.var}</tt>) leaves a <tt>.</tt> in a value as it
    # is, so a value can only contain <tt>.</tt> where it's clear where it
    # ends: a label expression with one variable that isn't exploded, set off
    # on both sides by the start or end of the URI or by characters that
    # label expansion encodes, such as <tt>/</tt>, <tt>?</tt> or <tt>;</tt>.
    # <tt>/f{.ext}</tt> extracts <tt>tar.gz</tt> from <tt>/f.tar.gz</tt>.
    # Elsewhere, each <tt>.</tt> starts a label: <tt>/{name}{.ext}</tt> reads
    # <tt>/archive.tar.gz</tt> as <tt>archive.tar</tt> and <tt>gz</tt>.
    #
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    #
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
    #   match = Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).match(uri, ExampleProcessor)
    #   match.variables
    #   #=> ["query"]
    #   match.captures
    #   #=> ["an example search query"]
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   match = Addressable::Template.new(
    #     "http://example.com/{first}/{+second}/"
    #   ).match(uri, ExampleProcessor)
    #   match.variables
    #   #=> ["first", "second"]
    #   match.captures
    #   #=> ["a", "b/c"]
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   match = Addressable::Template.new(
    #     "http://example.com/{first}{/second*}/"
    #   ).match(uri)
    #   match.variables
    #   #=> ["first", "second"]
    #   match.captures
    #   #=> ["a", ["b", "c"]]
    def match(uri, processor=nil)
      check_expressions
      # Text that isn't valid UTF-8 isn't a valid URI or IRI, so it doesn't
      # match, as below.
      return nil unless valid_utf8?(uri)
      unless uri.is_a?(Addressable::URI)
        begin
          uri = Addressable::URI.parse(uri)
        rescue Addressable::URI::InvalidURIError
          # Per the documented contract, match returns nil for any input
          # that doesn't match the template - including a string that
          # isn't even a valid URI.
          return nil
        end
      end
      mapping = {}

      # First, we need to process the pattern, and extract the values.
      expansions, expansion_regexp =
        parse_template_pattern(pattern, processor)

      matched = uri.to_str.match(expansion_regexp)
      return nil unless matched
      unparsed_values = matched.captures

      if uri.to_str == pattern
        return Addressable::Template::MatchData.new(uri, self, mapping)
      elsif expansions.size > 0
        index = 0
        expansions.each do |expansion|
          _, operator, varlist = *expansion.match(EXPRESSION)
          varlist.split(',').each do |varspec|
            _, name, modifier = *varspec.match(VARSPEC)
            mapping[name] ||= nil
            case operator
            when nil, '+', '#', '/', '.'
              unparsed_value = unparsed_values[index]
              name = varspec[VARSPEC, 1]
              value = unparsed_value
              value = value.split(JOINERS[operator]) if value && modifier == '*'
            when ';', '?', '&'
              if modifier == '*'
                if unparsed_values[index]
                  pairs = unparsed_values[index].split(JOINERS[operator])
                  pairs = pairs.map do |pair|
                    key, val = pair.split('=', 2)
                    [key, val || ""]
                  end
                  # An exploded list repeats the variable's name, where an
                  # associative array uses its own keys.
                  if !pairs.empty? && pairs.all? { |key, _| key == name }
                    value = pairs.map { |_, val| val }
                  else
                    value = pairs.inject({}) do |acc, (key, val)|
                      acc[key] = val
                      acc
                    end
                  end
                end
              else
                if (unparsed_values[index])
                  name, value = unparsed_values[index].split('=')
                  value = "" if value.nil?
                end
              end
            end
            if processor != nil && processor.respond_to?(:restore)
              value = processor.restore(name, value)
            end
            if processor == nil
              if value.is_a?(Hash)
                value = value.inject({}){|acc, (k, v)|
                  acc[Addressable::URI.unencode_component(k)] =
                    Addressable::URI.unencode_component(v)
                  acc
                }
              elsif value.is_a?(Array)
                value = value.map{|v| Addressable::URI.unencode_component(v) }
              else
                value = Addressable::URI.unencode_component(value)
              end
            end
            if !mapping.has_key?(name) || mapping[name].nil?
              # Doesn't exist, set to value (even if value is nil)
              mapping[name] = value
            end
            index = index + 1
          end
        end
        return Addressable::Template::MatchData.new(uri, self, mapping)
      else
        return nil
      end
    end

    ##
    # Expands a URI template into another URI template.
    #
    # @param [Hash, #each_pair, #[]] mapping
    #   The values for the template's variables. This can be a Hash, an
    #   array of name and value pairs, an object with <tt>each_pair</tt>
    #   such as a Struct, or any object that responds to <tt>[]</tt>, such as
    #   a lambda. A lambda or other <tt>[]</tt> object is called with each
    #   variable's name as a String, at most once per name. Leave the mapping
    #   out to look up variables with a block instead.
    #
    #   Lookups follow the <tt>Hash#fetch</tt> convention: raise
    #   <tt>KeyError</tt> for a variable that's missing, and return <tt>nil</tt>
    #   for a variable that's undefined. A missing variable's expression stays
    #   in the returned template, and an undefined variable is expanded to
    #   nothing, as with a Hash that lacks the key or maps it to <tt>nil</tt>.
    #   An object that responds to <tt>key?</tt> reports missing variables with
    #   <tt>key?</tt> instead.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
    # @param [Boolean] normalize_values
    #   Optional flag to enable/disable unicode normalization. Default: true
    #
    # The object should respond to either the <tt>validate</tt> or
    # <tt>transform</tt> messages or both. Both the <tt>validate</tt> and
    # <tt>transform</tt> methods should take two parameters: <tt>name</tt> and
    # <tt>value</tt>. The <tt>validate</tt> method should return <tt>true</tt>
    # or <tt>false</tt>; <tt>true</tt> if the value of the variable is valid,
    # <tt>false</tt> otherwise. An <tt>InvalidTemplateValueError</tt>
    # exception will be raised if the value is invalid. The <tt>transform</tt>
    # method should return the transformed variable value as a <tt>String</tt>.
    # If a <tt>transform</tt> method is used, the value will not be percent
    # encoded automatically. Unicode normalization will be performed both
    # before and after sending the value to the transform method.
    #
    # RFC 6570 doesn't define partial expansion, and it can't always give
    # the same result as expanding every variable at once:
    #
    # * In an expression with several variables whose values are joined
    #   with "," (<tt>{x,y}</tt>, <tt>{+x,y}</tt> and <tt>{#x,y}</tt>), there's
    #   no way to write a "," that appears only if a missing variable is
    #   later defined. The partial result assumes that missing variables
    #   stay undefined: <tt>{x,y}</tt> with only <tt>x</tt> gives
    #   <tt>1{y}</tt>, so expanding <tt>y</tt> later gives <tt>12</tt>, not
    #   <tt>1,2</tt>.
    # * In a form-style query (<tt>{?x,y}</tt>), the given variables come
    #   first, so that the query still starts with "?" if a missing variable
    #   is never given: <tt>{?x,y}</tt> with only <tt>y</tt> gives
    #   <tt>?y=2{&x}</tt>. The query has the same pairs, in another order.
    #
    # The result is a template, not a URI, so <tt>#pattern</tt> can differ
    # from <tt>#expand</tt> even when every variable is given: literals stay
    # as written, rather than pct-encoded, and a "#" after the one that
    # starts the fragment isn't encoded until the template is expanded. A
    # missing variable's expression stays in the template, where
    # <tt>#expand</tt> leaves it out.
    #
    # @yield [name] Looks up a variable, when no mapping is given.
    # @yieldparam [String] name The variable's name.
    # @yieldreturn [Object] The variable's value, or <tt>nil</tt> if it's
    #   undefined. Raise <tt>KeyError</tt> if the variable is missing.
    #
    # @raise [TypeError] If the mapping isn't one of the types above.
    # @raise [ArgumentError] If both a mapping and a block are given, or
    #   neither.
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    #
    # @return [Addressable::Template] The partially expanded URI template.
    #
    # @example
    #   Addressable::Template.new(
    #     "http://example.com/{one}/{two}/"
    #   ).partial_expand({"one" => "1"}).pattern
    #   #=> "http://example.com/1/{two}/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/{?one,two}"
    #   ).partial_expand({"one" => "1"}).pattern
    #   #=> "http://example.com/?one=1{&two}"
    #
    #   Addressable::Template.new(
    #     "http://example.com/{?one,two,three}"
    #   ).partial_expand({"one" => "1", "three" => 3}).pattern
    #   #=> "http://example.com/?one=1{&two}&three=3"
    #
    #   values = {"one" => "1"}
    #   Addressable::Template.new(
    #     "http://example.com/{one}/{two}/"
    #   ).partial_expand { |name| values.fetch(name) }.pattern
    #   #=> "http://example.com/1/{two}/"
    def partial_expand(mapping=NO_MAPPING, processor=nil, normalize_values=true,
                       &block)
      check_expressions
      result = self.pattern.dup
      mapping = resolve_mapping(mapping, block)
      result.gsub!( EXPRESSION ) do |capture|
        transform_partial_capture(mapping, capture, processor, normalize_values)
      end
      return Addressable::Template.new(result)
    end

    ##
    # Expands a URI template into a full URI.
    #
    # @param [Hash, #each_pair, #[]] mapping
    #   The values for the template's variables. This can be a Hash, an
    #   array of name and value pairs, an object with <tt>each_pair</tt>
    #   such as a Struct, or any object that responds to <tt>[]</tt>, such as
    #   a lambda. A lambda or other <tt>[]</tt> object is called with each
    #   variable's name as a String, at most once per name. Leave the mapping
    #   out to look up variables with a block instead.
    #
    #   Lookups follow the <tt>Hash#fetch</tt> convention: raise
    #   <tt>KeyError</tt> for a variable that's missing, and return <tt>nil</tt>
    #   for a variable that's undefined. Both expand to nothing. An object that
    #   responds to <tt>key?</tt> reports missing variables with <tt>key?</tt>
    #   instead.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
    # @param [Boolean] normalize_values
    #   Optional flag to enable/disable unicode normalization. Default: true
    #
    # The object should respond to either the <tt>validate</tt> or
    # <tt>transform</tt> messages or both. Both the <tt>validate</tt> and
    # <tt>transform</tt> methods should take two parameters: <tt>name</tt> and
    # <tt>value</tt>. The <tt>validate</tt> method should return <tt>true</tt>
    # or <tt>false</tt>; <tt>true</tt> if the value of the variable is valid,
    # <tt>false</tt> otherwise. An <tt>InvalidTemplateValueError</tt>
    # exception will be raised if the value is invalid. The <tt>transform</tt>
    # method should return the transformed variable value as a <tt>String</tt>.
    # If a <tt>transform</tt> method is used, the value will not be percent
    # encoded automatically. Unicode normalization will be performed both
    # before and after sending the value to the transform method.
    #
    # @yield [name] Looks up a variable, when no mapping is given.
    # @yieldparam [String] name The variable's name.
    # @yieldreturn [Object] The variable's value, or <tt>nil</tt> if it's
    #   undefined. Raise <tt>KeyError</tt> if the variable is missing.
    #
    # @raise [TypeError] If the mapping isn't one of the types above.
    # @raise [ArgumentError] If both a mapping and a block are given, or
    #   neither.
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
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
    #   Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).expand(
    #     {"query" => "an example search query"},
    #     ExampleProcessor
    #   ).to_str
    #   #=> "http://example.com/search/an+example+search+query/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).expand(
    #     {"query" => "an example search query"}
    #   ).to_str
    #   #=> "http://example.com/search/an%20example%20search%20query/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).expand(
    #     {"query" => "bogus!"},
    #     ExampleProcessor
    #   ).to_str
    #   #=> Addressable::Template::InvalidTemplateValueError
    #
    #   repository = {"owner" => "sporkmonger", "repo" => "addressable"}
    #   Addressable::Template.new(
    #     "https://github.com/{owner}/{repo}"
    #   ).expand { |name| repository.fetch(name) }.to_str
    #   #=> "https://github.com/sporkmonger/addressable"
    def expand(mapping=NO_MAPPING, processor=nil, normalize_values=true,
               &block)
      check_expressions
      mapping = resolve_mapping(mapping, block)
      result = map_literals(self.pattern) do |literal|
        Addressable::URI.encode_component(literal, LITERAL_ENCODE)
      end
      result.gsub!( EXPRESSION ) do |capture|
        transform_capture(mapping, capture, processor, normalize_values)
      end
      return Addressable::URI.parse(encode_later_number_signs(result))
    end

    ##
    # Returns an Array of variables used within the template pattern.
    # The variables are listed in the Array in the order they appear within
    # the pattern.  Multiple occurrences of a variable within a pattern are
    # not represented in this Array.
    #
    # @return [Array] The variables present in the template's pattern.
    def variables
      (@variables ||= ordered_variable_defaults.map { |var, val| var }.uniq).dup
    end
    alias_method :keys, :variables
    alias_method :names, :variables

    ##
    # Returns a mapping of variables to their default values specified
    # in the template. Variables without defaults are not returned.
    #
    # @return [Hash] Mapping of template variables to their defaults
    def variable_defaults
      (@variable_defaults ||=
        Hash[*ordered_variable_defaults.reject { |k, v| v.nil? }.flatten]).dup
    end

    ##
    # Coerces a template into a `Regexp` object. This regular expression will
    # behave very similarly to the actual template, and should match the same
    # URI values, but it cannot fully handle, for example, values that would
    # extract to an `Array`.
    #
    # Each variable has a named group. A group name can't start with a digit,
    # so a variable whose name does has its group named with a leading ".":
    # `{42}` has the group `.42`. Ruby 2.3 and earlier only allow a letter or
    # "_" as the first character of a group name, so there a variable whose
    # name starts with anything else has its group named with "__" before
    # and after it: `{42}` has `__42__`, and `{%41}` has `__%41__`.
    #
    # @return [Regexp] A regular expression which should match the template.
    #
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    def to_regexp
      check_expressions
      _, source = parse_template_pattern(pattern)
      Regexp.new(source)
    end

    ##
    # Returns the source of the coerced `Regexp`.
    #
    # @return [String] The source of the `Regexp` given by {#to_regexp}.
    #
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    #
    # @api private
    def source
      self.to_regexp.source
    end

    ##
    # Returns the named captures of the coerced `Regexp`.
    #
    # @return [Hash] The named captures of the `Regexp` given by {#to_regexp}.
    #
    # @raise [Addressable::Template::InvalidTemplateError]
    #   If the template doesn't match the RFC 6570 grammar, e.g. an unclosed
    #   expression or a stray <tt>}</tt>.
    #
    # @api private
    def named_captures
      captures = self.to_regexp.named_captures
      captures.each_with_object({}) do |(group, indexes), names|
        names[variable_name(group)] = indexes
      end
    end

  private
    ##
    # Raises InvalidTemplateError for the first part of the pattern that
    # isn't a literal or an expression (RFC 6570 section 3).
    def check_expressions
      position = 0
      pattern.scan(TEMPLATE_TOKEN) do |token|
        if token.start_with?("}")
          raise InvalidTemplateError, "Unmatched \"}\" at position #{position}"
        elsif token.start_with?("{")
          if !token.end_with?("}")
            raise InvalidTemplateError,
              "Unclosed template expression #{token.inspect} " \
              "at position #{position}"
          elsif token !~ VALID_EXPRESSION
            if RESERVED_OPERATORS.include?(token[1])
              raise InvalidTemplateOperatorError,
                "Invalid template operator #{token[1].inspect} in " \
                "#{token.inspect} at position #{position}"
            end
            raise InvalidTemplateError,
              "Invalid template expression #{token.inspect} " \
              "at position #{position}"
          end
        end
        position += token.length
      end
    end

    def ordered_variable_defaults
      @ordered_variable_defaults ||= begin
        expansions, _ = parse_template_pattern(pattern)
        expansions.flat_map do |capture|
          _, _, varlist = *capture.match(EXPRESSION)
          varlist.split(',').map do |varspec|
            varspec[VARSPEC, 1]
          end
        end
      end
    end


    ##
    # Loops through each capture and expands any values available in mapping
    #
    # @param [Hash] mapping
    #   Set of keys to expand
    # @param [String] capture
    #   The expression to expand
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
    # @param [Boolean] normalize_values
    #   Optional flag to enable/disable unicode normalization. Default: true
    #
    # The object should respond to either the <tt>validate</tt> or
    # <tt>transform</tt> messages or both. Both the <tt>validate</tt> and
    # <tt>transform</tt> methods should take two parameters: <tt>name</tt> and
    # <tt>value</tt>. The <tt>validate</tt> method should return <tt>true</tt>
    # or <tt>false</tt>; <tt>true</tt> if the value of the variable is valid,
    # <tt>false</tt> otherwise. An <tt>InvalidTemplateValueError</tt> exception
    # will be raised if the value is invalid. The <tt>transform</tt> method
    # should return the transformed variable value as a <tt>String</tt>. If a
    # <tt>transform</tt> method is used, the value will not be percent encoded
    # automatically. Unicode normalization will be performed both before and
    # after sending the value to the transform method.
    #
    # @return [String] The expanded expression
    def transform_partial_capture(mapping, capture, processor = nil,
                                  normalize_values = true)
      _, operator, varlist = *capture.match(EXPRESSION)
      operator ||= ""
      vars = varlist.split(",")
      given = lambda { |varspec| mapping.key?(varspec[VARSPEC, 1]) }
      defined = lambda do |varspec|
        given.call(varspec) &&
          !defined_value(mapping[varspec[VARSPEC, 1]]).nil?
      end

      if vars.all?(&given)
        return transform_capture(mapping, capture, processor, normalize_values)
      elsif vars.none?(&given)
        return capture
      end

      if operator == "?"
        # partial expansion of form style query variables sometimes requires a
        # slight reordering of the variables to produce a valid url.
        first_to_expand = vars.find(&defined)

        vars = [first_to_expand] + vars.reject {|varspec| varspec == first_to_expand}  if first_to_expand
      end

      # An undefined variable adds nothing, so it mustn't split the missing
      # variables around it into separate expressions, which would lose the
      # separator between them or repeat the operator's prefix.
      vars = vars.select { |v| !given.call(v) || defined.call(v) }

      # Consecutive variables that are all given, or all missing, stay in one
      # expression, so that their separator is kept.
      runs = vars.chunk { |varspec| given.call(varspec) }.to_a
      if %w(+ #).include?(operator) || operator.empty?
        transform_partial_comma_runs(
          mapping, operator, runs, defined, processor, normalize_values
        )
      else
        runs.inject("".dup) do |acc, (is_given, run)|
          expression = "{#{operator}#{run.join(',')}}"
          if is_given
            value = transform_capture(
              mapping, expression, processor, normalize_values
            )
            # After a value, the rest of a query continues with "&".
            operator = "&" if operator == "?" && !value.empty?
            acc << value
          else
            acc << expression
          end
        end
      end
    end

    ##
    # Partially expands the runs of a simple, reserved or fragment expression,
    # whose values are separated by commas. RFC 6570 has no expression that
    # adds a comma only if a later variable is defined, so the result is the
    # same as expanding at once only if each missing variable ends up
    # undefined. After the first value, a fragment expression's runs use
    # reserved expansion, which adds no second "#".
    #
    # @param [Hash] mapping The mapping to replace captures
    # @param [String] operator The expression's operator.
    # @param [Array] runs The given and missing runs of varspecs.
    # @param [Proc] defined Whether a varspec's variable is given and defined.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
    # @param [Boolean] normalize_values
    #   Optional flag to enable/disable unicode normalization. Default: true
    #
    # @return [String] The partially expanded expression
    def transform_partial_comma_runs(mapping, operator, runs, defined,
                                     processor, normalize_values)
      started = false
      # Once a given variable is defined, a fragment expression's "#" is
      # certain, so it comes first, and every run uses reserved expansion.
      fragment = operator == "#" &&
        runs.any? { |is_given, run| is_given && run.any?(&defined) }
      result = fragment ? "#".dup : "".dup
      runs.inject(result) do |acc, (is_given, run)|
        run_operator = (started || fragment) && operator == "#" ? "+" : operator
        expression = "{#{run_operator}#{run.join(',')}}"
        if is_given
          # An empty string is defined, so it still takes a separator.
          if run.any?(&defined)
            acc << "," if started
            started = true
          end
          acc << transform_capture(
            mapping, expression, processor, normalize_values
          )
        else
          acc << expression
        end
      end
    end

    ##
    # Replaces the literal text between the expressions of a pattern.
    #
    # @param [String] pattern The URI template pattern.
    #
    # @yield [literal] Each run of literal text.
    #
    # @return [String] The pattern with each literal replaced.
    def map_literals(pattern)
      result = "".dup
      # StringScanner works in byte offsets; character offsets would make
      # this quadratic for a pattern with non-ASCII characters.
      scanner = StringScanner.new(pattern)
      while (text = scanner.scan_until(EXPRESSION))
        expression = scanner.matched
        literal = text.byteslice(0, text.bytesize - expression.bytesize)
        result << yield(literal, expression) << expression
      end
      result << yield(scanner.rest, nil)
    end

    ##
    # A URI fragment can't contain "#" (RFC 3986 section 3.5), so expansion
    # encodes every "#" after the first one, which starts the fragment.
    #
    # @param [String] uri The expanded URI.
    #
    # @return [String] The URI with any later "#" encoded as "%23".
    def encode_later_number_signs(uri)
      start = uri.index('#')
      return uri unless start
      uri[0..start] + uri[(start + 1)..-1].gsub('#', '%23')
    end

    ##
    # Builds a regular expression for a non-ASCII character, as it is or
    # pct-encoded in either case.
    #
    # @param [String] character The character.
    #
    # @return [String] The regular expression source.
    def either_form(character)
      encoded = Addressable::URI.encode_component(character, LITERAL_ENCODE)
      "(?:#{Regexp.escape(character)}|(?i:#{encoded}))"
    end

    ##
    # Builds a regular expression for literal text. A non-ASCII character,
    # written as it is or as pct-encoded UTF-8, matches either way, since
    # expansion pct-encodes it (RFC 6570 section 3.1). So does a "#" that
    # expansion may have encoded because a fragment had already started.
    #
    # @param [String] literal The literal text.
    # @param [TrueClass, FalseClass] fragment
    #   Whether a fragment may have started before the literal.
    #
    # @return [String] The regular expression source.
    def literal_regexp(literal, fragment = false)
      literal.scan(LITERAL_TOKEN).map do |token|
        if token == '#'
          source = fragment ? NUMBER_SIGN_EITHER_FORM : '\\#'
          fragment = true
          source
        elsif token =~ LITERAL_ENCODE
          token.each_char.map { |character| either_form(character) }.join
        elsif token.length > 3 || token =~ /\A%[89A-Fa-f]/
          decoded = Addressable::URI.unencode_component(token).dup
          decoded.force_encoding(Encoding::UTF_8)
          if decoded.valid_encoding?
            decoded.each_char.map { |character| either_form(character) }.join
          else
            "(?i:#{Regexp.escape(token)})"
          end
        else
          Regexp.escape(token)
        end
      end.join
    end

    ##
    # Takes the first characters of a value for a prefix modifier. Reserved
    # and fragment expansion count a pct-encoded triplet as one character,
    # so that it isn't split (RFC 6570 section 2.4.1).
    #
    # @param [String] value The value
    # @param [Integer] length The maximum number of characters
    # @param [Boolean] allow_reserved Whether pct-encoded triplets are kept
    #
    # @return [String] The prefix
    def prefix(value, length, allow_reserved)
      value = value.to_str
      return value[0...length] unless allow_reserved
      return value.scan(PCT_ENCODED_OR_CHARACTER).first(length).join if
        value.valid_encoding?
      # A regular expression can't scan text that isn't valid UTF-8, but its
      # characters can be read one at a time, each invalid byte as one.
      hex = lambda do |character|
        character && character.bytesize == 1 &&
          HEX_DIGITS.include?(character.getbyte(0))
      end
      characters = value.each_char.to_a
      tokens = []
      until characters.empty? || tokens.size == length
        if characters[0] == "%" && hex.call(characters[1]) &&
            hex.call(characters[2])
          tokens << characters.shift(3).join
        else
          tokens << characters.shift
        end
      end
      tokens.join
    end

    ##
    # Drops the undefined (nil) members of a list or associative array value.
    # RFC 6570 treats a list or associative array with no defined members as
    # undefined, as it does nil.
    #
    # @param [Object] value The mapped value
    #
    # @return [Object, nil] The value without its undefined members, or nil
    #   if the value is undefined
    def defined_value(value)
      value = if value.kind_of?(Hash)
        value.reject { |_, member| member.nil? }
      elsif value.respond_to?(:to_ary)
        value.to_ary.reject { |member| member.nil? }
      else
        value
      end
      value unless value == {} || value == []
    end

    ##
    # Transforms a mapped value so that values can be substituted into the
    # template.
    #
    # @param [Hash] mapping The mapping to replace captures
    # @param [String] capture
    #   The expression to replace
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
    # @param [Boolean] normalize_values
    #   Optional flag to enable/disable unicode normalization. Default: true
    #
    #
    # The object should respond to either the <tt>validate</tt> or
    # <tt>transform</tt> messages or both. Both the <tt>validate</tt> and
    # <tt>transform</tt> methods should take two parameters: <tt>name</tt> and
    # <tt>value</tt>. The <tt>validate</tt> method should return <tt>true</tt>
    # or <tt>false</tt>; <tt>true</tt> if the value of the variable is valid,
    # <tt>false</tt> otherwise. An <tt>InvalidTemplateValueError</tt> exception
    # will be raised if the value is invalid. The <tt>transform</tt> method
    # should return the transformed variable value as a <tt>String</tt>. If a
    # <tt>transform</tt> method is used, the value will not be percent encoded
    # automatically. Unicode normalization will be performed both before and
    # after sending the value to the transform method.
    #
    # @return [String] The expanded expression
    def transform_capture(mapping, capture, processor=nil,
                          normalize_values=true)
      _, operator, varlist = *capture.match(EXPRESSION)
      return_value = varlist.split(',').inject([]) do |acc, varspec|
        _, name, modifier = *varspec.match(VARSPEC)
        value = defined_value(mapping[name])
        unless value.nil?
          allow_reserved = %w(+ #).include?(operator)
          # Common primitives where the .to_s output is well-defined
          if Numeric === value || Symbol === value ||
              value == true || value == false
            value = value.to_s
          end
          length = modifier.gsub(':', '').to_i if modifier =~ /^:\d+/

          unless (Hash === value) ||
            value.respond_to?(:to_ary) || value.respond_to?(:to_str)
            raise TypeError,
              "Can't convert #{value.class} into String or Array."
          end
          # RFC 6570 section 2.4.1
          if length && (Hash === value || value.respond_to?(:to_ary))
            raise InvalidTemplateValueError,
              "The prefix modifier #{modifier} can't be applied to the " \
              "list or associative array #{name.inspect}."
          end

          value = normalize_value(value) if normalize_values

          if processor == nil || !processor.respond_to?(:transform)
            # Handle percent escaping
            if allow_reserved
              encode_map = RESERVED_ENCODE
            else
              encode_map = Addressable::URI::CharacterClasses::UNRESERVED
            end
            if value.kind_of?(Array)
              transformed_value = value.map do |val|
                if length
                  Addressable::URI.encode_component(
                    prefix(val, length, allow_reserved), encode_map)
                else
                  Addressable::URI.encode_component(val, encode_map)
                end
              end
              unless modifier == "*"
                transformed_value = transformed_value.join(',')
              end
            elsif value.kind_of?(Hash)
              transformed_value = value.map do |key, val|
                if modifier == "*"
                  "#{
                    Addressable::URI.encode_component( key, encode_map)
                  }=#{
                    Addressable::URI.encode_component( val, encode_map)
                  }"
                else
                  "#{
                    Addressable::URI.encode_component( key, encode_map)
                  },#{
                    Addressable::URI.encode_component( val, encode_map)
                  }"
                end
              end
              unless modifier == "*"
                transformed_value = transformed_value.join(',')
              end
            else
              if length
                transformed_value = Addressable::URI.encode_component(
                  prefix(value, length, allow_reserved), encode_map)
              else
                transformed_value = Addressable::URI.encode_component(
                  value, encode_map)
              end
            end
          end

          # Process, if we've got a processor
          if processor != nil
            if processor.respond_to?(:validate)
              if !processor.validate(name, value)
                display_value = value.kind_of?(Array) ? value.inspect : value
                raise InvalidTemplateValueError,
                  "#{name}=#{display_value} is an invalid template value."
              end
            end
            if processor.respond_to?(:transform)
              transformed_value = processor.transform(name, value)
              if normalize_values
                transformed_value = normalize_value(transformed_value)
              end
            end
          end
          # A list or associative array with a member isn't empty, even if
          # its members join to an empty string (RFC 6570 section 3.2.7).
          composite = Hash === value || value.respond_to?(:to_ary)
          acc << [name, transformed_value, composite]
        end
        acc
      end
      return "" if return_value.empty?
      join_values(operator, return_value)
    end

    ##
    # Takes a set of values, and joins them together based on the
    # operator.
    #
    # @param [String, Nil] operator One of the operators from the set
    #   (?,&,+,#,;,/,.), or nil if there wasn't one.
    # @param [Array] return_value
    #   The set of return values (as [variable_name, value] tuples) that will
    #   be joined together.
    #
    # @return [String] The transformed mapped value
    def join_values(operator, return_value)
      leader = LEADERS.fetch(operator, '')
      joiner = JOINERS.fetch(operator, ',')
      case operator
      when '&', '?'
        leader + return_value.map{|k,v|
          if v.is_a?(Array) && v.first =~ /=/
            v.join(joiner)
          elsif v.is_a?(Array)
            v.map{|inner_value| "#{k}=#{inner_value}"}.join(joiner)
          else
            "#{k}=#{v}"
          end
        }.join(joiner)
      when ';'
        # An empty member or pair value gets no "=" (RFC 6570 appendix A).
        # Values are pct-encoded, so a pair that ends in "=" is empty.
        return_value.map{|k,v,composite|
          if v.is_a?(Array) && v.first =~ /=/
            ';' + v.map{|pair| pair.end_with?('=') ? pair[0...-1] : pair}.
              join(";")
          elsif v.is_a?(Array)
            ';' + v.map{|inner_value|
              inner_value == '' ? k : "#{k}=#{inner_value}"
            }.join(";")
          else
            (v && v != '') || composite ? ";#{k}=#{v}" : ";#{k}"
          end
        }.join
      else
        leader + return_value.map{|k,v| v}.join(joiner)
      end
    end

    ##
    # Takes a set of values, and joins them together based on the
    # operator.
    #
    # @param [Hash, Array, String] value
    #   Normalizes unicode keys and values with String#unicode_normalize (NFC)
    #
    # @return [Hash, Array, String] The normalized values
    def normalize_value(value)
      # Handle unicode normalization
      if value.respond_to?(:to_ary)
        value = value.to_ary.map { |val| normalize_value(val) }
      elsif value.kind_of?(Hash)
        value = value.inject({}) { |acc, (k, v)|
          acc[normalize_value(k)] = normalize_value(v)
          acc
        }
      else
        value = value.to_s if !value.kind_of?(String)
        value = utf8_value(value)
        # Text that isn't valid UTF-8 can't be normalized; its bytes are
        # pct-encoded as they are.
        value = value.unicode_normalize(:nfc) if value.valid_encoding?
      end
      value
    end

    ##
    # A value as UTF-8. RFC 6570 section 3.2.1 transcodes a value in another
    # character encoding to UTF-8. A binary or US-ASCII value, or one that
    # isn't valid in its own encoding, is read as UTF-8 as it is.
    #
    # @param [String] value The value.
    #
    # @return [String] The value in UTF-8, which may not be valid UTF-8.
    def utf8_value(value)
      encoding = value.encoding
      return value if encoding == Encoding::UTF_8
      if encoding != Encoding::BINARY && encoding != Encoding::US_ASCII &&
          value.valid_encoding?
        begin
          return value.encode(Encoding::UTF_8)
        rescue EncodingError
          # A character with no Unicode equivalent keeps its bytes.
        end
      end
      value.dup.force_encoding(Encoding::UTF_8)
    end

    ##
    # Whether a URI's text is valid UTF-8, read as UTF-8 whatever its
    # encoding, as Addressable::URI reads it.
    #
    # @param [Addressable::URI, #to_str] uri The URI.
    #
    # @return [TrueClass, FalseClass]
    def valid_utf8?(uri)
      return true unless uri.respond_to?(:to_str)
      text = uri.to_str
      text = text.dup.force_encoding(Encoding::UTF_8) unless
        text.encoding == Encoding::UTF_8
      text.valid_encoding?
    end

    ##
    # Picks the mapping to expand with: the one passed, or the block.
    #
    # @param [Object] mapping The mapping argument
    # @param [Proc, nil] block The block
    #
    # @return [Hash, MappingLookup] The normalized mapping
    def resolve_mapping(mapping, block)
      if block
        unless mapping.equal?(NO_MAPPING) || mapping.nil?
          raise ArgumentError, "Pass a mapping or a block, not both."
        end
        return normalize_keys(block)
      end
      if mapping.equal?(NO_MAPPING)
        raise ArgumentError, "A mapping or a block is required."
      end
      normalize_keys(mapping)
    end

    ##
    # Generates a hash with string keys, or a lookup for a mapping that isn't
    # enumerable
    #
    # @param [Hash, #each_pair, #inject, #[]] mapping A mapping to normalize
    #
    # @return [Hash, MappingLookup]
    #   A hash with stringified keys, or a lookup
    def normalize_keys(mapping)
      if mapping.respond_to?(:each_pair)
        pairs = mapping.to_enum(:each_pair)
      elsif mapping.respond_to?(:inject)
        pairs = mapping
      elsif mapping.respond_to?(:[]) && !mapping.respond_to?(:to_str) &&
          !(Symbol === mapping) && !(Numeric === mapping)
        return MappingLookup.new(mapping)
      else
        raise TypeError, "Can't convert #{mapping.class} into a mapping."
      end
      return pairs.inject({}) do |accu, pair|
        name, value = pair
        if Symbol === name
          name = name.to_s
        elsif name.respond_to?(:to_str)
          name = name.to_str
        else
          raise TypeError,
            "Can't convert #{name.class} into String."
        end
        accu[name] = value
        accu
      end
    end

    ##
    # The name of the regular expression group for a variable. A group name
    # can't start with a digit, which a variable name can (RFC 6570 section
    # 2.3), so such a name gets a leading ".". No variable name starts with
    # ".", so this can't collide with another variable's group. Ruby 2.3 and
    # earlier only allow a letter or "_" as the first character, so there a
    # name that starts with a digit or a pct-encoded triplet is wrapped in
    # "__" instead.
    #
    # @param [String] name The variable name.
    #
    # @return [String] The group name.
    def capture_name(name)
      if GROUP_NAME_CAN_START_WITH_DOT
        name =~ /\A[0-9]/ ? ".#{name}" : name
      else
        name =~ /\A[A-Za-z_]/ ? name : "__#{name}__"
      end
    end

    ##
    # The variable name for a regular expression group name.
    #
    # @param [String] group The group name.
    #
    # @return [String] The variable name.
    def variable_name(group)
      if GROUP_NAME_CAN_START_WITH_DOT
        group.start_with?(".") ? group[1..-1] : group
      else
        group =~ /\A__([^A-Za-z_].*)__\z/m ? $1 : group
      end
    end

    ##
    # Generates the <tt>Regexp</tt> that parses a template pattern. Memoizes the
    # value if template processor not set (processors may not be deterministic)
    #
    # @param [String] pattern The URI template pattern.
    # @param [#match] processor The template processor to use.
    #
    # @return [Array, Regexp]
    #   An array of expansion variables nad a regular expression which may be
    #   used to parse a template pattern
    def parse_template_pattern(pattern, processor = nil)
      if processor.nil? && pattern == @pattern
        @cached_template_parse ||=
          parse_new_template_pattern(pattern, processor)
      else
        parse_new_template_pattern(pattern, processor)
      end
    end

    ##
    # Describes what follows each expression in a template pattern.
    #
    # @param [String] escaped_pattern The escaped URI template pattern.
    #
    # @return [Array<Array>] For each expression, the <tt>MatchData</tt> of
    #   the expression directly after it (or <tt>nil</tt>), and whether the
    #   text after it could start with a comma.
    def expression_followers(escaped_pattern)
      expressions = escaped_pattern.to_enum(:scan, EXPRESSION).map do
        Regexp.last_match
      end
      expressions.each_with_index.map do |current, index|
        following = expressions[index + 1]
        following = nil unless following && following.begin(0) == current.end(0)
        # Expressions can match nothing, so look past any that can't start
        # with a comma.
        position = current.end(0)
        comma = expressions[(index + 1)..-1].any? do |later|
          break false unless later.begin(0) == position
          position = later.end(0)
          may_start_with_comma?(later[1], later[2])
        end
        [following, comma || escaped_pattern[position] == ',']
      end
    end

    ##
    # Whether a label expression's value can contain ".". Label expansion
    # leaves a "." in a value as it is (RFC 6570 section 3.2.5), so where the
    # value ends is only known where the expression is delimited by the start
    # or end of the URI or by characters that can't be part of its expansion
    # (section 1.4): a lone, unexploded variable, with a reserved character
    # in the literal text since the previous expression, and a reserved
    # character next, after any expressions that start with one when they
    # aren't empty. A "#" counts only if a fragment can't have started
    # before it, since expansion encodes a later one as "%23".
    #
    # @param [Integer] index The expression's index.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<TrueClass, FalseClass>] either_leader
    #   Whether a fragment may have started before each expression.
    # @param [Array<TrueClass, FalseClass>] either_literal
    #   Whether a fragment may have started before each literal.
    #
    # @return [TrueClass, FalseClass]
    def label_takes_dots?(index, expressions, literals, either_leader,
                          either_literal)
      _, operator, varlist = *expressions[index].match(EXPRESSION)
      return false unless operator == '.' && varlist =~ VARSPEC && $2 != '*'
      return false unless index == 0 || literals[index] =~ LABEL_DELIMITER
      position = index + 1
      while position < expressions.size && literals[position].empty?
        operator = expressions[position][1]
        return false unless "/?&;".include?(operator) ||
          (operator == '#' && !either_leader[position])
        position += 1
      end
      literal = literals[position]
      return true if literal.empty?
      literal[0] =~ LABEL_DELIMITER &&
        !(literal[0] == '#' && either_literal[position]) ? true : false
    end

    ##
    # Whether an expression could match a string that starts with a comma.
    #
    # @param [String, nil] operator The expression's operator.
    # @param [String] varlist The expression's variable list.
    #
    # @return [TrueClass, FalseClass]
    def may_start_with_comma?(operator, varlist)
      return false unless LEADERS.fetch(operator, '').empty?
      operator == '+' || !(varlist =~ VARSPEC && $2 != '*')
    end

    ##
    # Whether an expression, followed directly by another one, could only
    # match characters that the other one could also match, in any amount.
    #
    # @param [MatchData] following The expression that follows.
    # @param [String, nil] operator The operator of the first expression.
    # @param [Array<String>] varspecs The varspecs of the first expression.
    #
    # @return [TrueClass, FalseClass]
    def absorbed_by?(following, operator, varspecs)
      last = following[2].split(',').last
      case following[1]
      when '+'
        # An unexploded last variable matches any characters that an
        # expression can, and can end anywhere.
        last[VARSPEC, 2] != '*'
      when nil
        if last[VARSPEC, 2] == '*'
          # Matches any unreserved characters and commas.
          operator.nil? || operator == '.'
        elsif following[2] == last
          # Matches any unreserved characters.
          operator == '.' || (operator.nil? && varspecs.size == 1 &&
            varspecs.first[VARSPEC, 2] != '*')
        else
          false
        end
      else
        false
      end
    end

    ##
    # Generates the <tt>Regexp</tt> that parses a template pattern.
    #
    # @param [String] pattern The URI template pattern.
    # @param [#match] processor The template processor to use.
    #
    # @return [Array, Regexp]
    #   An array of expansion variables nad a regular expression which may be
    #   used to parse a template pattern
    def parse_new_template_pattern(pattern, processor = nil)
      # Escape the literal text between the expressions. Once a fragment
      # may have started, expansion encodes a later "#" as "%23", so the
      # literals and fragment expressions after that point match it either
      # way. Reserved and fragment expansion may start a fragment.
      fragment = false
      either_leader = []
      literals = []
      either_literal = []
      raw_expressions = []
      escaped_pattern = map_literals(pattern) do |literal, expression|
        literals << literal
        either_literal << fragment
        source = literal_regexp(literal, fragment)
        fragment ||= literal.include?('#')
        if expression
          raw_expressions << expression
          either_leader << fragment
          fragment ||= expression =~ /\A\{[+#]/ ? true : false
        end
        source
      end
      dotted_labels = raw_expressions.each_index.map do |index|
        label_takes_dots?(
          index, raw_expressions, literals, either_leader, either_literal
        )
      end

      expansions = []
      # Processor patterns can match anything, so they get 2.9.0's choices.
      plain_processor = !(processor && processor.respond_to?(:match))
      followers = expression_followers(escaped_pattern)

      # Create a regular expression that captures the values of the
      # variables in the URI.
      regexp_string = escaped_pattern.gsub( EXPRESSION ) do |expansion|

        index = expansions.size
        expansions << expansion
        _, operator, varlist = *expansion.match(EXPRESSION)
        leader = Regexp.escape(LEADERS.fetch(operator, ''))
        if operator == '#' && either_leader[index]
          leader = NUMBER_SIGN_EITHER_FORM
        end
        joiner = Regexp.escape(JOINERS.fetch(operator, ','))
        varspecs = varlist.split(',')
        results = varspecs.map do |varspec|
          name = varspec[VARSPEC, 1]
          processor && processor.respond_to?(:match) ? processor.match(name) : nil
        end
        # Without processor patterns, any variable in the expression can take
        # the characters that an earlier variable leaves, which lets the
        # variables after the first one have fewer choices below.
        plain = results.compact.empty?
        explodes = varspecs.map { |varspec| varspec[VARSPEC, 2] == '*' }
        first_explode = explodes.index(true)
        not_after_value =
          "(?<![#{Addressable::URI::CharacterClasses::UNRESERVED}])" \
          "(?<![^\\x00-\\x7F])"
        combined = varspecs.each_with_index.map do |varspec, position|
          _, name, modifier = *varspec.match(VARSPEC)
          name = capture_name(name)

          result = results[position]
          if result
            "(?<#{name}>#{ result })"
          else
            group = case operator
            when '+'
              "#{ RESERVED }*?"
            when '#'
              "#{ RESERVED }*?"
            when '/'
              "#{ UNRESERVED }*?"
            when '.'
              if dotted_labels[index]
                # Nothing after the value can continue it, so it takes every
                # character up to the delimiter.
                "#{ UNRESERVED }*+"
              else
                "#{ UNRESERVED.gsub('\.', '') }*?"
              end
            when ';'
              # The same strings, tried in the same order, as 2.9.0's
              # "U*=?U*?", but a name without "=" can only match one way.
              "(?:#{UNRESERVED}*=#{UNRESERVED}*?|#{UNRESERVED}*)"
            when '?'
              "#{ UNRESERVED }*=#{ UNRESERVED }*?"
            when '&'
              "#{ UNRESERVED }*=#{ UNRESERVED }*?"
            else
              "#{ UNRESERVED }*?"
            end
            if modifier == '*'
              # The ; ? and & members match the same strings, in the same
              # order of preference, as 2.9.0's members joined by an optional
              # joiner, but each character can only belong to one member.
              seg = case operator
                    when '+', '#' then "#{RESERVED_NO_COMMA}*+"
                    when ';' then "(?:#{UNRESERVED}|=)*"
                    when '?', '&'
                      "#{UNRESERVED}*=(?:#{UNRESERVED}*=)*#{UNRESERVED}*?"
                    else group
                    end
              # The joiner between exploded members must be mandatory. With
              # an optional joiner, a run of members can be partitioned in
              # exponentially many ways, which backtracks catastrophically on
              # engines without match memoization (MRI < 3.2, JRuby,
              # TruffleRuby).
              value = "#{seg}(?:#{joiner}#{seg})*"
            end
            if plain && first_explode && position > first_explode &&
                (operator == '+' || operator == '#' || operator == ';')
              # Exploded values were tried longest first, so whatever this
              # variable could match after the first exploded one, that one
              # already tried matching itself. Only the last unexploded + or
              # # variable can stop inside a member, where an exploded
              # variable can't. As in 2.9.0, a variable is the last one if
              # its varspec is the same as the last varspec.
              if operator == ';'
                "(?<#{name}>)"
              elsif modifier != '*' && varspec == varspecs.last
                "(?<#{name}>#{RESERVED_NO_COMMA}*?)?"
              else
                # 2.9.0 skipped the variable when it couldn't be empty.
                "(?:(?<#{name}>)(?!#{RESERVED_NO_COMMA}))?"
              end
            elsif plain && modifier == '*' && explodes[(position + 1)..-1].any? &&
                (operator.nil? || operator == '/' || operator == '.')
              # Exploded values were tried shortest first, and a later
              # exploded variable can match whatever this one leaves, so once
              # a split fails, every split where this variable is longer
              # fails too. Of the values tried, only the leading joiners are
              # shorter than every value tried before them.
              "(?<#{name}>(?:#{joiner})*)"
            elsif plain && position > 0 && explodes[position - 1] &&
                (operator == '?' || operator == '&')
              # Whatever this variable could match after an exploded one,
              # that one already tried matching itself, unless it couldn't:
              # an exploded member can't be empty, so this variable may only
              # start right after an empty one.
              "(?<#{name}>(?<=#{leader}#{joiner}|#{joiner}#{joiner})" \
                "#{value || group})?"
            elsif operator == ';' && plain && position > 0
              # Values were tried longest first, and splitting an earlier
              # variable's run of characters with this one never gave a
              # different result, so this one may only start after that run.
              "(?<#{name}>(?:#{not_after_value}#{value || group})?)"
            elsif modifier == '*'
              "(?<#{name}>#{value})?"
            elsif varspecs.size > 1 && (operator == '+' || operator == '#') &&
                  varspec != varspecs.last
              "(?<#{name}>#{RESERVED_NO_COMMA}*+)?"
            elsif plain && position < varspecs.size - 1 &&
                  (operator.nil? || operator == '/' || operator == '.')
              # Values were tried shortest first, so a run of characters
              # without a joiner went to a later variable. The only other
              # value that could change the result is the whole run up to the
              # next joiner.
              "(?<#{name}>(?:#{group}(?=#{joiner}))??)"
            else
              "(?<#{name}>#{group})?"
            end
          end
        end
        following, comma_follows = followers[index]
        single = varspecs.size == 1 && varspecs.first[VARSPEC, 2] != '*'
        if plain_processor && following &&
            absorbed_by?(following, operator, varspecs)
          # Each expression tried its empty alternative first. When the next
          # one follows it directly and can match anything it could, followed
          # by anything the next one could match on its own, every other
          # choice ends where the empty one can also end, so the empty
          # alternative always gave the first match.
          leader = "(?!)#{leader}"
          combined = combined.join("#{joiner}?")
        elsif plain_processor && single && following &&
            following[1].nil? && following[2] =~ VARSPEC && $2 != '*' &&
            (operator == '+' || operator == '#')
          # Values were tried shortest first, and the next expression can
          # match any unreserved characters, so the value only needs to end
          # after a character that the next expression couldn't match.
          combined = "(?<#{capture_name(varspecs.first[VARSPEC, 1])}>" \
            "#{RESERVED}*?#{not_after_value})?"
        elsif plain && varspecs.size > 1 &&
            (operator == '+' || operator == '#') &&
            !comma_follows &&
            varspecs.none? { |varspec| varspec[VARSPEC, 2] == '*' } &&
            !varspecs[0...-1].include?(varspecs.last)
          # 2.9.0 tried each value with the joiner after it first, then the
          # value on its own, then skipping the variable, and every other
          # choice gave a value to a later variable that an earlier one had
          # already been tried with. A variable after a skipped one is
          # skipped too. Stopping before a joiner is left out, so this is
          # only used when no joiner can follow the expression. As in 2.9.0,
          # a variable is the last one if its varspec is the same as the
          # last varspec.
          nested = varspecs[0...-1].reverse.inject("") do |inner, varspec|
            "(?:(?<#{capture_name(varspec[VARSPEC, 1])}>" \
              "#{RESERVED_NO_COMMA}*+)" \
              "#{joiner}?+#{inner}|(?=#{RESERVED_NO_COMMA}))"
          end
          combined = nested + combined.last
        else
          combined = combined.join("#{joiner}?")
        end
        "(?:|#{leader}#{combined})"
      end

      # Ensure that the regular expression matches the whole URI.
      regexp_string = "\\A#{regexp_string}\\z"
      return expansions, Regexp.new(regexp_string)
    end

  end
end
