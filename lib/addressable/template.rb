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


require "set"
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

    # The operators that write each variable's name before its value.
    NAMED_OPERATORS = [';', '?', '&'].freeze
    private_constant :NAMED_OPERATORS

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
    #   In a <tt>;</tt>, <tt>?</tt> or <tt>&</tt> expression, the pattern
    #   matches the value after the variable's name and <tt>=</tt>, and
    #   <tt>restore</tt> is called with the template's variable names.
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
    # Matching takes time linear in the URI's length, with two exceptions on
    # MRI before 3.3, JRuby and TruffleRuby, where it can take time
    # polynomial in the URI's length: matching with a processor that gives a
    # variable its own pattern, which keeps every choice open so that the
    # pattern decides the values, and matching some templates that combine an
    # exploded variable, or several variables in one expression, with other
    # expressions, such as <tt>{+c*,d}{&b}.{b}</tt>.
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
    #   In a <tt>;</tt>, <tt>?</tt> or <tt>&</tt> expression, the pattern
    #   matches the value after the variable's name and <tt>=</tt>, and
    #   <tt>restore</tt> is called with the template's variable names.
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
    # Matching takes time linear in the URI's length, with two exceptions on
    # MRI before 3.3, JRuby and TruffleRuby, where it can take time
    # polynomial in the URI's length: matching with a processor that gives a
    # variable its own pattern, which keeps every choice open so that the
    # pattern decides the values, and matching some templates that combine an
    # exploded variable, or several variables in one expression, with other
    # expressions, such as <tt>{+c*,d}{&b}.{b}</tt>.
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
      expansions, expansion_regexp, patterns =
        parse_template_pattern(pattern, processor)

      matched = uri.to_str.match(expansion_regexp)
      return nil unless matched
      unparsed_values = matched.captures

      if uri.to_str == pattern
        return Addressable::Template::MatchData.new(uri, self, mapping)
      elsif expansions.size > 0
        index = 0
        split = !(processor && processor.respond_to?(:match))
        expansions.each_with_index do |expansion, expansion_index|
          _, operator, varlist = *expansion.match(EXPRESSION)
          varspecs = varlist.split(',')
          if NAMED_OPERATORS.include?(operator)
            named = named_values(
              operator, varspecs, unparsed_values[index, varspecs.size],
              patterns[expansion_index]
            )
            return nil unless named
          end
          values = if split && varspecs.size > 1
            split_from_left(operator, varspecs, matched, index)
          end
          if !values && [nil, '+', '#', '/', '.'].include?(operator) &&
              varlist.include?('*')
            members = exploded_members(
              operator, varspecs, unparsed_values[index, varspecs.size],
              index, matched, uri.to_str
            )
          end
          varspecs.each_with_index do |varspec, position|
            _, name, modifier = *varspec.match(VARSPEC)
            mapping[name] ||= nil
            case operator
            when nil, '+', '#', '/', '.'
              unparsed_value = unparsed_values[index]
              name = varspec[VARSPEC, 1]
              value = unparsed_value
              if values
                value = values[position]
              elsif value && modifier == '*'
                value = members[position]
              end
            when ';', '?', '&'
              # An exploded value is an associative array, even when its
              # pairs repeat the variable's name, as an exploded list's do.
              # A repeated key keeps its last value.
              value = named[position]
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
    # The members of each exploded value of a default, +, #, / or .
    # expression in a match. A member can be empty, so a joiner at the end of
    # a value can be an empty member or the one before a later variable, and
    # an empty value can be one empty member or none. Joined with the
    # expression's joiner, the values must give the text the expression
    # matched, so where the first choice doesn't, the others are tried.
    #
    # @param [String, nil] operator The expression's operator.
    # @param [Array<String>] varspecs The expression's variables.
    # @param [Array<String, nil>] values The variables' captures.
    # @param [Integer] index The index of its first capture.
    # @param [MatchData] matched The match.
    # @param [String] text The URI.
    #
    # @return [Hash] The members, for each exploded variable's position.
    def exploded_members(operator, varspecs, values, index, matched, text)
      joiner = JOINERS.fetch(operator, ',')
      exploded = varspecs.map { |varspec| varspec[VARSPEC, 2] == '*' }
      # An empty list is undefined, and has no joiner before it.
      valued = lambda do |at|
        values[at] && !(exploded[at] && values[at].empty?)
      end
      members = {}
      choices = {}
      varspecs.each_index do |position|
        next unless exploded[position] && values[position]
        list = values[position].split(joiner, -1)
        # Right after the leader, an empty value is one empty member.
        if list.empty? && position == 0 && LEADERS.key?(operator)
          list = ['']
        end
        # A later variable that starts right where this value ends has its
        # joiner at the end of this one.
        reached = matched.end(index + position + 1)
        ((position + 1)...varspecs.size).each do |at|
          next unless valued.call(at)
          group = index + at + 1
          list.pop if matched.begin(group) == reached && list.last == ''
          break unless matched.end(group) == matched.begin(group)
          reached = matched.end(group)
        end
        members[position] = list
        # The other choices: up to one fewer empty member at the end for
        # each later variable, or one empty member for an empty value.
        whole = values[position].split(joiner, -1)
        options = [list]
        (0..[varspecs.size - position - 1, whole.size].min).each do |dropped|
          next unless whole[(whole.size - dropped)..-1].all?(&:empty?)
          options << whole[0, whole.size - dropped]
        end
        options << [''] if whole.empty?
        choices[position] = options.uniq
      end
      present = values.each_index.select { |at| values[at] }
      return members if present.empty? || choices.empty?
      expected = text[
        matched.begin(index + present.first + 1)...
          matched.end(index + present.last + 1)
      ]
      joined = lambda do |chosen|
        values.each_index.map do |at|
          next nil unless values[at]
          next values[at] unless exploded[at]
          list = chosen[at]
          list.empty? ? nil : list.join(joiner)
        end.compact.join(joiner)
      end
      return members if joined.call(members) == expected
      positions = choices.keys
      count = positions.inject(1) { |product, at| product * choices[at].size }
      # The choices are few for templates of the usual size; past that,
      # the first one is kept rather than trying them all.
      return members if count > 64
      combos = positions.map { |at| choices[at] }
      first, *rest = combos
      first.product(*rest).each do |combo|
        chosen = Hash[positions.zip(combo)]
        return chosen if joined.call(chosen) == expected
      end
      members
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
    # not represented in this Array. An expression that doesn't match the
    # RFC 6570 grammar, such as <tt>{!var}</tt> or <tt>{var:0}</tt>, has no
    # variables to list.
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
        # An expression with a reserved operator has no variables to list.
        expansions.grep(VALID_EXPRESSION).flat_map do |capture|
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
    #   Normalizes unicode keys and values to NFC, leaving a run of more than
    #   30 combining marks as it is
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
        if value.valid_encoding?
          value = UnicodeNormalization.normalize(value, :nfc)
        end
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
    # Splits the text an expression matched among its variables, when
    # more than one split would expand to it. RFC 6570 doesn't say which
    # split to choose, so each variable, from the first, takes as much as it
    # can: an exploded variable every member left, and any other variable
    # one member, except that the last variable of a + or # expression,
    # whose values may contain commas, takes the rest. A variable with
    # nothing left is undefined. So {/a*,b} reads /x/y as a = ["x", "y"]
    # and {/a,b*} reads /x/y/z as a = "x" and b = ["y", "z"].
    #
    # @return [Array, nil] Each variable's unparsed value, or nil for an
    #   operator whose values aren't split by position, an expression that
    #   repeats a name, or when the variables can't take every member.
    def split_from_left(operator, varspecs, matched, index)
      return nil unless [nil, '+', '#', '/', '.'].include?(operator)
      # A name used twice must have one value; that isn't split here.
      names = varspecs.map { |varspec| varspec[VARSPEC, 1] }
      return nil if names.uniq.size < names.size
      groups = ((index + 1)..(index + varspecs.size)).select do |group|
        matched[group]
      end
      return nil if groups.empty?
      joiner = JOINERS.fetch(operator, ',')
      text = matched.string[matched.begin(groups.first)...matched.end(groups.last)]
      members = text.split(joiner, -1)
      members = [''] if members.empty?
      last = varspecs.size - 1
      values = varspecs.each_with_index.map do |varspec, position|
        if members.empty?
          nil
        elsif varspec[VARSPEC, 2] == '*'
          members.slice!(0..-1)
        elsif position == last && (operator == '+' || operator == '#')
          members.slice!(0..-1).join(joiner)
        else
          members.shift
        end
      end
      members.empty? ? values : nil
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
    # The pair that a ;, ? or & variable that isn't exploded can match: one
    # of the names of the expression's variables that aren't exploded, then
    # "=" and the value. A ; variable's empty value is written as the name
    # alone. With processor patterns, each name's value is matched with its
    # own variable's pattern.
    #
    # @param [String] operator The expression's operator.
    # @param [Array<String>] varspecs The expression's varspecs.
    # @param [Array<String, nil>] results The processor patterns, by varspec.
    #
    # @return [String, nil] The regular expression source, or nil if every
    #   variable is exploded.
    def named_pair_source(operator, varspecs, results)
      choices = {}
      varspecs.each_with_index do |varspec, position|
        next if varspec[VARSPEC, 2] == '*'
        name = varspec[VARSPEC, 1]
        choices[name] = results[position] unless choices.key?(name)
      end
      return nil if choices.empty?
      value = "#{UNRESERVED}*?"
      # A longer name is tried first, so a name isn't taken for the start of
      # a longer one.
      choices = choices.sort_by { |name, _| -name.size }
      if results.compact.empty?
        names = choices.map { |name, _| named_variable_source(name) }
        names = "(?:#{names.join('|')})"
        if operator == ';'
          "#{names}(?:=#{value})?"
        else
          "#{names}=#{value}"
        end
      else
        pairs = choices.map do |name, result|
          source = named_variable_source(name)
          pair = "#{source}=(?:#{result || value})"
          if operator == ';' &&
              (result.nil? || Regexp.new("\\A(?:#{result})\\z") =~ "")
            pair += "|#{source}"
          end
          pair
        end
        "(?:#{pairs.join('|')})"
      end
    end

    ##
    # A variable's name as ;, ? and & expansion writes it, as a regular
    # expression source. Its pct-encoded triplets match in either case.
    #
    # @param [String] name The variable name.
    #
    # @return [String] The regular expression source.
    def named_variable_source(name)
      name.scan(/%[0-9A-Fa-f]{2}|[^%]+/).map do |part|
        part.start_with?('%') ? "(?i:#{Regexp.escape(part)})" : Regexp.escape(part)
      end.join
    end

    ##
    # A variable's name with its pct-encoded triplets in upper case, so that
    # names written with either case compare equal.
    #
    # @param [String] name The variable name.
    #
    # @return [String] The name.
    def canonical_name(name)
      name.gsub(/%[0-9A-Fa-f]{2}/) { |triplet| triplet.upcase }
    end

    ##
    # The values of a ;, ? or & expression's variables. A pair with the name
    # of one of the expression's variables that aren't exploded is that
    # variable's, wherever it is, and an exploded variable gets the others.
    # Each name is only given as many times as the expression has it.
    #
    # @param [String] operator The expression's operator.
    # @param [Array<String>] varspecs The expression's varspecs.
    # @param [Array<String, nil>] captures The text each variable matched.
    # @param [Array<String, nil>] results The processor patterns, by varspec.
    #
    # @return [Array, nil] The value for each varspec, or nil if a name is
    #   given too many times or a value doesn't match its pattern.
    def named_values(operator, varspecs, captures, results)
      places = {}
      varspecs.each_with_index do |varspec, position|
        next if varspec[VARSPEC, 2] == '*'
        (places[canonical_name(varspec[VARSPEC, 1])] ||= []) << position
      end
      values = Array.new(varspecs.size)
      taken = Hash.new(0)
      give = lambda do |name, value|
        key = canonical_name(name)
        positions = places[key]
        return false unless positions && taken[key] < positions.size
        values[positions[taken[key]]] = value
        taken[key] += 1
        true
      end
      joiner = Regexp.escape(JOINERS[operator])
      names = varspecs.reject { |varspec| varspec[VARSPEC, 2] == '*' }.map do |varspec|
        named_variable_source(varspec[VARSPEC, 1])
      end.uniq
      # A pair starts after a joiner that one of the names follows.
      pair_start = /#{joiner}(?=(?:#{names.join('|')})(?:=|#{joiner}|\z))/
      varspecs.each_with_index do |varspec, position|
        capture = captures[position]
        # The run of pairs is in the first such variable's place, and the
        # others match nothing.
        next if capture.nil? || capture.empty? || varspec[VARSPEC, 2] == '*'
        capture.split(pair_start).each do |pair|
          name, value = pair.split('=', 2)
          return nil unless give.call(name, value || "")
        end
      end
      varspecs.each_with_index do |varspec, position|
        capture = captures[position]
        next if capture.nil? || varspec[VARSPEC, 2] != '*'
        pairs = {}
        claimed = false
        capture.split(JOINERS[operator]).each do |pair|
          key, value = pair.split('=', 2)
          value ||= ""
          # An empty member has no name, so it stays the exploded variable's.
          positions = key && places[canonical_name(key)]
          if positions
            # A value in an exploded variable's place is checked against
            # its own variable's pattern, as it is in its own place.
            pattern = results[positions.first]
            return nil if pattern && value !~ /\A(?:#{pattern})\z/
            return nil unless give.call(key, value)
            claimed = true
          else
            pairs[key] = value
          end
        end
        values[position] = claimed && pairs.empty? ? nil : pairs
      end
      values
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
    # @return [Array<Array>] For each expression, the expression directly
    #   after it (or <tt>nil</tt>), as an array of the expression, its
    #   operator and its variable list, and whether the text after it could
    #   start with a comma.
    def expression_followers(escaped_pattern)
      # StringScanner works in byte offsets; character offsets would make
      # this quadratic for a pattern with non-ASCII characters.
      scanner = StringScanner.new(escaped_pattern)
      expressions = []
      while scanner.skip_until(EXPRESSION)
        finish = scanner.pos
        expressions << [
          [scanner[0], scanner[1], scanner[2]],
          finish - scanner.matched_size,
          finish
        ]
      end
      # Expressions can match nothing, so the text after an expression could
      # start with a comma if the expression directly after it could, or if
      # the text after that one could. Working backwards, each answer comes
      # from the next one, which keeps this linear for a long run of
      # expressions.
      followers = Array.new(expressions.size)
      comma = false
      (expressions.size - 1).downto(0) do |index|
        current_end = expressions[index][2]
        following, following_start, _ = expressions[index + 1]
        if following && following_start == current_end
          comma ||= may_start_with_comma?(following[1], following[2])
        else
          following = nil
          comma = escaped_pattern.byteslice(current_end, 1) == ','
        end
        followers[index] = [following, comma]
      end
      followers
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
    # Whether the text after an expression could start with a character.
    #
    # @param [Integer] index The expression's index.
    # @param [String] character The character.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    #
    # @return [TrueClass, FalseClass]
    def may_follow_with?(index, character, expressions, literals)
      position = index + 1
      loop do
        literal = literals[position]
        return literal.start_with?(character) unless literal.empty?
        return false if position == expressions.size
        operator = expressions[position][EXPRESSION, 1]
        leader = LEADERS.fetch(operator, '')
        if leader.empty?
          return true if may_contain?(expressions[position], character)
        elsif leader == character || (operator == '#' && character == '%')
          return true
        end
        # The expression can match nothing.
        position += 1
      end
    end

    ##
    # Whether what follows an expression always starts with a character that
    # a + or # member can contain, other than a comma: literal text that
    # does, after expressions that are empty or start with a leader, or with
    # characters other than a comma. The URI can't end there.
    #
    # @param [Integer] index The expression's index.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    #
    # @return [TrueClass, FalseClass]
    def members_follow?(index, expressions, literals)
      position = index + 1
      loop do
        literal = literals[position]
        unless literal.empty?
          return literal =~ /\A#{RESERVED}/ && literal[0] != ',' ? true : false
        end
        return false if position == expressions.size
        expression = expressions[position]
        # A leader is a member's character. Without one, the expression can
        # start with any character it can contain.
        if LEADERS.fetch(expression[EXPRESSION, 1], '').empty?
          return false if may_contain?(expression, ',')
        end
        # The expression can also be empty.
        position += 1
      end
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
    # @param [Array] following
    #   The expression that follows, its operator and its variable list.
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
    # Whether an expression's expansion can contain a character.
    #
    # @param [String] expression The expression.
    # @param [String] character The character.
    #
    # @return [TrueClass, FalseClass]
    def may_contain?(expression, character)
      # Any expansion can contain a pct-encoded triplet, and matching accepts
      # a non-ASCII character as it is.
      return true if character == '%' || character =~ LITERAL_ENCODE
      contained_characters(expression).include?(character)
    end

    ##
    # The characters of TEXT_CHARACTERS that an expression's expansion can
    # contain.
    #
    # @param [String] expression The expression.
    #
    # @return [Array<String>]
    def contained_characters(expression)
      _, operator, varlist = *expression.match(EXPRESSION)
      # A joiner only comes between values.
      CONTAINED_CHARACTERS.fetch([operator, varlist =~ /[,*]/ ? true : false])
    end

    ##
    # The characters of TEXT_CHARACTERS that any of some expressions'
    # expansions can contain.
    #
    # @param [Array<String>] expressions The expressions.
    #
    # @return [Array<String>]
    def characters_in(expressions)
      # Expressions of the same kind share one set.
      expressions.map { |expression| contained_characters(expression) }.
        uniq(&:object_id).inject([], :|)
    end

    ##
    # The characters of TEXT_CHARACTERS that match a regexp source for one
    # character.
    #
    # @param [String] group The source.
    #
    # @return [Array<String>]
    def group_characters(group)
      GROUP_CHARACTERS.fetch(group) do
        TEXT_CHARACTERS.select { |c| c =~ /\A#{group}\z/ }
      end
    end

    ##
    # Splits a template pattern into its expressions and the literal text
    # around them, with the regular expression for each literal. Once a
    # fragment may have started, expansion encodes a later "#" as "%23", so
    # the literals and fragment expressions after that point match it either
    # way. Reserved and fragment expansion may start a fragment.
    #
    # @param [String] pattern The URI template pattern.
    #
    # @return [Array]
    #   The pattern with its literals escaped, its expressions, its
    #   literals (the text before each expression, and after the last one),
    #   their regular expression sources, and whether a fragment may have
    #   started before each expression and before each literal.
    def template_parts(pattern)
      fragment = false
      either_leader = []
      literals = []
      either_literal = []
      expressions = []
      literal_sources = []
      escaped_pattern = map_literals(pattern) do |literal, expression|
        literals << literal
        either_literal << fragment
        source = literal_regexp(literal, fragment)
        literal_sources << source
        fragment ||= literal.include?('#')
        if expression
          expressions << expression
          either_leader << fragment
          fragment ||= expression =~ /\A\{[+#]/ ? true : false
        end
        source
      end
      [escaped_pattern, expressions, literals, literal_sources, either_leader,
       either_literal]
    end

    ##
    # The characters such that text made of one can be put in front of an
    # expression's value, so that the expression matches it and everything
    # after it the same way.
    #
    # @param [String] expression The expression.
    # @param [Array<String>] characters The characters to check.
    #
    # @return [Array<String>] Those of the characters that can.
    def absorbed(expression, characters)
      _, operator, varlist = *expression.match(EXPRESSION)
      return [] unless operator.nil? || operator == '+'
      varspecs = varlist.split(',')
      exploded = varspecs.first[VARSPEC, 2] == '*'
      # Text in front of a lone exploded value becomes part of its first
      # member, or, with a comma, members of their own. A + member takes
      # every character it can, so it couldn't end where it did, unless
      # only unexploded variables follow it: the text up to its last comma
      # then becomes members, and the rest becomes part of the next value.
      return [] if exploded && !(operator.nil? && varspecs.size == 1) &&
        !(varspecs.size > 1 &&
          varspecs.drop(1).none? { |varspec| varspec[VARSPEC, 2] == '*' })
      # The first of several + variables takes every character it can, or
      # is skipped, so text in front of it would be taken past where the
      # value ended.
      return [] if operator == '+' && !exploded && varspecs.size > 1
      group = group_characters(operator ? RESERVED : UNRESERVED).join
      characters.select do |character|
        if character == ',' && (exploded || varspecs.size > 1)
          # A comma would end the first of several variables.
          exploded
        else
          group.include?(character) || character == '%' ||
            character =~ LITERAL_ENCODE
        end
      end
    end

    ##
    # Whether an expression tries the places where it can end in order,
    # nearest first, as a lone variable of the default, +, #, / or .
    # operator does. In a block of such expressions, the first choice that
    # lets literal text match ends the block as early as any choice can.
    #
    # @param [String] expression The expression.
    #
    # @return [TrueClass, FalseClass]
    def ends_in_order?(expression)
      _, operator, varlist = *expression.match(EXPRESSION)
      [nil, '+', '#', '/', '.'].include?(operator) &&
        varlist =~ VARSPEC && $2 != '*' ? true : false
    end

    # Characters that a template's text can contain, other than those that
    # every expression can.
    TEXT_CHARACTERS = (("!".."~").to_a - ["%"]).freeze
    # The thread-local key of the cache for one template build.
    BUILD_CACHE = :__addressable_template_build
    # For each operator, including those RFC 6570 reserves, and whether the
    # expression can join several values, the characters of TEXT_CHARACTERS
    # that its expansion can contain.
    CONTAINED_CHARACTERS = [nil, *"+#./;?&=,!@|".chars].
      product([false, true]).each_with_object({}) do |(op, joins), table|
        reserved = op == '+' || op == '#'
        others = [LEADERS.fetch(op, ''),
          joins ? JOINERS.fetch(op, ',') : '',
          op && ";?&".include?(op) ? '=' : ''].join
        table[[op, joins]] = TEXT_CHARACTERS.select do |character|
          (reserved &&
            character =~ /[#{Addressable::URI::CharacterClasses::RESERVED}]/) ||
            character =~ /[#{Addressable::URI::CharacterClasses::UNRESERVED}]/ ||
            others.include?(character)
        end.freeze
      end.freeze
    # The characters of TEXT_CHARACTERS that an operator's value can contain.
    GROUP_CHARACTERS = [RESERVED, UNRESERVED].each_with_object({}) do |group, table|
      table[group] =
        TEXT_CHARACTERS.select { |c| c =~ /\A#{group}\z/ }.freeze
    end.freeze
    private_constant :TEXT_CHARACTERS, :CONTAINED_CHARACTERS, :GROUP_CHARACTERS,
      :BUILD_CACHE

    ##
    # Whether a regexp source is valid for the regular expression engine.
    #
    # @param [String] source The source.
    #
    # @return [TrueClass, FalseClass]
    def valid_regexp?(source)
      Regexp.new(source)
      true
    rescue RegexpError
      false
    end

    ##
    # A lookahead that checks the end of the URI once: where literal text is
    # one character that nothing after it can contain, it's the last one in
    # the URI, so what follows it there must match the rest of the template.
    # Otherwise, a URI whose end doesn't match would be tried with every
    # choice before it. The last such literal text is used, so that the
    # rest is as short as possible.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<String>] literal_sources The regexp source of each literal.
    # @param [Array<String>] expression_sources The regexp source of each
    #   expression.
    #
    # @return [String, nil] The lookahead's source, or nil if there's none.
    def tail_check(expressions, literals, literal_sources, expression_sources)
      (expressions.size - 2).downto(0) do |index|
        literal = literals[index + 1]
        next unless literal.size == 1 && TEXT_CHARACTERS.include?(literal) &&
          literal_sources[index + 1] == Regexp.escape(literal)
        outside, final =
          characters_after(index, expressions, literals, index + 2)
        next unless (outside - final_characters(final)).include?(literal)
        rest = ((index + 1)...expressions.size).map do |later|
          expression_sources[later] + literal_sources[later + 1]
        end.join
        # The rest is matched again in the template's own regexp, so its
        # groups don't capture here. The empty group keeps a group around a
        # single repetition from warning that it's redundant.
        rest = rest.gsub(/\(\?<(?![=!])[^>]*>/, '(?:(?:)')
        source = "(?=(?:#{character_set([literal], true)}*+" \
          "#{Regexp.escape(literal)})*+#{rest}\\z)"
        return source if valid_regexp?("\\A#{source}")
      end
      nil
    end

    ##
    # A lookahead that checks the end of the URI once, where the template
    # ends with literal text and then an expression that starts with a
    # leader its values can't contain, and that can contain the literal
    # text's characters: the literal text must be followed by
    # a match of the expression that ends the URI, after the first place
    # where the literal text before it is. Otherwise, a URI whose end doesn't
    # match would be tried with every choice before it. Since each match of
    # the expression ends before the next leader, the check takes linear
    # time.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<String>] literal_sources The regexp source of each literal.
    # @param [Array<String>] expression_sources The regexp source of each
    #   expression.
    #
    # @return [String, nil] The lookahead's source, or nil if there's none.
    def ending_check(expressions, literals, literal_sources,
                     expression_sources)
      return nil if expressions.size < 2 || !literals.last.empty? ||
        literals[-2].empty?
      _, operator, varlist = *expressions.last.match(EXPRESSION)
      leader = LEADERS[operator]
      return nil unless leader
      # A value's character or a joiner that's the leader would let the
      # expression's matches overlap.
      values = group_characters(operator == '#' ? RESERVED : UNRESERVED)
      joiner = varlist =~ /[,*]/ ? JOINERS.fetch(operator, ',') : nil
      return nil if values.include?(leader) || joiner == leader
      # Otherwise, the expression's matches can't run past a place where the
      # literal text is, and nothing is gained.
      return nil unless (literals[-2].chars & TEXT_CHARACTERS).all? do |c|
        may_contain?(expressions.last, c)
      end
      rest = expression_sources.last.gsub(/\(\?<(?![=!])[^>]*>/, '(?:(?:)')
      earlier = (expressions.size - 2).downto(0).find do |index|
        !literals[index].empty?
      end
      # The first place where the earlier literal text is.
      first = earlier ? "(?>[\\s\\S]*?(?=#{literal_sources[earlier]}))" : ""
      # Its parts are all parts of the template's own regexp, so unlike a
      # lookbehind, it's always valid.
      "(?=#{first}[\\s\\S]*?#{literal_sources[-2]}#{rest}\\z)"
    end

    ##
    # Lookaheads for a template with a block of expressions that doesn't
    # commit at the literal text after it. Without them, a URI that doesn't
    # match would be tried with every way of dividing the text before that
    # literal text among the block's values, each time matching the rest of
    # the template again. Both only check what every match has:
    #
    # * The literal text after the first expression, in order. Each is
    #   found at its first place after the one before, which is no later
    #   than where any match has it.
    # * After the literal text that follows the first block that doesn't
    #   commit, the rest of the template, up to the end of the URI, from
    #   some place where that literal text is. Each place is tried once.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<String>] literal_sources The regexp source of each literal.
    # @param [Array<String>] expression_sources The regexp source of each
    #   expression.
    # @param [Array<Integer>] ends The indexes of the expressions that end
    #   blocks.
    #
    # @return [String] The lookaheads' source, empty if there are none.
    def open_block_checks(expressions, literals, literal_sources,
                          expression_sources, ends)
      open = (0...(expressions.size - 1)).find do |index|
        !ends.include?(index) && !literals[index + 1].empty?
      end
      return "" unless open
      # Each literal's place is found, and then matching moves past its first
      # character, so that the next is found after it.
      order = (1...literals.size).reject { |index| literals[index].empty? }.
        map { |index| "(?>[\\s\\S]*?(?=#{literal_sources[index]}))[\\s\\S]" }
      source = "(?=#{order.join})"
      # Only an exploded value in the block gives it more ways to divide the
      # text than the block's other checks bound, so only the order is
      # checked otherwise, and only where the literal text after the block
      # can be written two ways, as a "#" can be "%23": the block's values can
      # then end at either form, and divide the text before it in every way.
      start = (ends.select { |index| index < open }.max || -1) + 1
      unless expressions[start..open].any? { |e| e[EXPRESSION, 2].include?('*') }
        either = literal_sources[open + 1] != Regexp.escape(literals[open + 1])
        return either && valid_regexp?("\\A#{source}") ? source : ""
      end
      # The rest is matched from every place where the literal text is, so
      # it's checked only where matching itself would reach each of them: a
      # template that starts with a lone + value, which can take anything.
      # Where nothing before the literal text can contain its first
      # character, it's at the first place where that character is, so the
      # rest is matched only from there.
      rest = ((open + 1)...expressions.size).map do |later|
        expression_sources[later] + literal_sources[later + 1]
      end.join.gsub(/\(\?<(?![=!])[^>]*>/, '(?:(?:)')
      literal = literals[open + 1]
      _, operator, varlist = *expressions.first.match(EXPRESSION)
      varspecs = varlist.split(',')
      # Otherwise, the rest is matched from each place that matching itself
      # reaches: where the template starts with the block, with no literal
      # text in it, and its first expression can match any text of its
      # characters, with the others empty. Every place the block can reach,
      # it reaches that way only if that expression can contain everything
      # the others can.
      absorbing = start == 0 && literals[1..open].all?(&:empty?) &&
        (operator.nil? || operator == '+') &&
        (varspecs.size == 1 || varlist.include?('*')) &&
        (characters_in(expressions[0..open]) -
          contained_characters(expressions.first)).empty?
      if literal_sources[open + 1].start_with?(Regexp.escape(literal[0])) &&
          TEXT_CHARACTERS.include?(literal[0]) &&
          literals[0..open].none? { |text| text.include?(literal[0]) } &&
          expressions[0..open].none? { |e| may_contain?(e, literal[0]) }
        source += "(?=#{character_set([literal[0]], true)}*+" \
          "#{literal_sources[open + 1]}#{rest}\\z)"
      elsif absorbing
        within = value_class(contained_characters(expressions.first))
        source += "(?=#{literal_sources.first}#{within}*?" \
          "#{literal_sources[open + 1]}#{rest}\\z)"
      end
      valid_regexp?("\\A#{source}") ? source : ""
    end

    ##
    # The expressions after whose literal text a block ends, so that
    # matching commits to the block's choices. A block ends after literal
    # text where every expression in it tries its ends in order and the next
    # value can take anything the block could, so the first choice that lets
    # the literal text match is the one every later choice would also lead
    # to.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<TrueClass, FalseClass>] empties
    #   Whether each expression only matches nothing.
    #
    # @return [Array<Integer>] The expressions' indexes.
    def block_ends(expressions, literals, empties)
      ends = Set.new
      # The characters that the block could match.
      characters = []
      # Whether every expression in the block ends in order.
      ordered = true
      expressions.each_with_index do |expression, index|
        ordered &&= empties[index] || ends_in_order?(expression)
        characters |= contained_characters(expression)
        literal = literals[index + 1]
        characters |= literal.chars
        next if !ordered || literal.empty? || index + 1 == expressions.size
        following = (index + 1...expressions.size).find do |later|
          !empties[later]
        end
        next unless following && (following == index + 1 ||
          literals[(index + 2)..following].all?(&:empty?))
        next unless
          (characters - absorbed(expressions[following], characters)).empty?
        ends << index
        characters = []
        ordered = true
      end
      ends
    end

    ##
    # Puts together the regular expression for a template from the sources
    # for its literal text and its expressions.
    #
    # Matching goes left to right in blocks. A block ends after literal text
    # where whatever the block could match, and that text, could also be put
    # in front of the next value: the first choice that lets that text match
    # is then the one that 2.9.x would end up with, since any later choice
    # only moves text from the block to the next value. Matching commits to
    # it, so that a URI that doesn't match isn't tried with every way of
    # dividing it among the variables, which takes polynomial time on
    # engines that don't memoize (MRI < 3.3, JRuby and TruffleRuby).
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<String>] literal_sources The regexp source of each literal.
    # @param [Array<String>] expression_sources The regexp source of each
    #   expression.
    # @param [Array<TrueClass, FalseClass>] empties
    #   Whether each expression only matches nothing, because the one after
    #   it takes whatever it could.
    # @param [TrueClass, FalseClass] commit
    #   Whether to commit to choices. With processor patterns, which can
    #   match anything, every choice is kept open.
    # @param [Array<Integer>] ends
    #   The indexes of the expressions that end blocks, if already found.
    #
    # @return [String] The regular expression's source.
    def assemble_regexp(expressions, literals, literal_sources,
                        expression_sources, empties = [], commit = true,
                        ends = nil)
      regexp = "\\A".dup
      if commit
        # A URI with a character that nothing in the template can match is
        # rejected before anything is tried. Otherwise, a choice that fails
        # only there would be tried with every choice before it.
        allowed = literals.join.chars | characters_in(expressions)
        allowed = allowed.reject { |character| character =~ LITERAL_ENCODE }
        regexp << "(?=(?:[#{allowed.map { |c| Regexp.escape(c) }.join}]|" \
          "%[0-9A-Fa-f]{2}|[^\\x00-\\x7F])*+\\z)"
        # The same goes for literal text that ends the template, which the
        # URI must end with. It's checked behind the end, since a literal
        # before \z in a lookahead keeps some engines from anchoring the
        # match at the start; literal text that can be written more than one
        # way can't be checked there, and isn't checked.
        unless expressions.empty? || literals.last.empty?
          ending = "(?=[\\s\\S]*+\\z(?<=#{literal_sources.last}))"
          regexp << ending if valid_regexp?(ending)
        end
        tail = tail_check(expressions, literals, literal_sources,
                          expression_sources)
        regexp << tail if tail
        last_value = ending_check(expressions, literals, literal_sources,
                                  expression_sources)
        regexp << last_value if last_value
        ends ||= block_ends(expressions, literals, empties)
        regexp << open_block_checks(expressions, literals, literal_sources,
                                    expression_sources, ends)
      end
      regexp << literal_sources.first
      ends ||= commit ? block_ends(expressions, literals, empties) : []
      block = "".dup
      expressions.each_index do |index|
        block << expression_sources[index] << literal_sources[index + 1]
        next unless ends.include?(index)
        regexp << "(?>#{block})"
        block = "".dup
      end
      "#{regexp}#{block}\\z"
    end

    ##
    # The regexp source for a character class with a set of ASCII
    # characters, pct-encoded triplets and non-ASCII characters.
    #
    # @param [Array<String>] characters The ASCII characters.
    #
    # @return [String]
    def value_class(characters)
      others = "[^\\x00-\\x7F]|%[a-fA-F0-9][a-fA-F0-9]"
      return "(?:#{others})" if characters.empty?
      "(?:#{character_set(characters)}|#{others})"
    end

    ##
    # The regexp source for a set of ASCII characters.
    #
    # @param [Array<String>] characters The characters.
    # @param [TrueClass, FalseClass] negated Whether to match any other one.
    #
    # @return [String]
    def character_set(characters, negated = false)
      "[#{negated ? '^' : ''}#{characters.map { |c| Regexp.escape(c) }.join}]"
    end

    ##
    # The characters that literal text can be matched with: its own, and
    # those of a non-ASCII character pct-encoded, in either case. (A "#"
    # that can be "%23" is handled where its value ends.)
    #
    # @param [String] literal The literal text.
    #
    # @return [Array<String>]
    def literal_characters(literal)
      build_memo([:literal, literal]) { uncached_literal_characters(literal) }
    end

    ##
    # Works out #literal_characters.
    #
    # @param (see #literal_characters)
    #
    # @return (see #literal_characters)
    def uncached_literal_characters(literal)
      literal.chars.flat_map do |character|
        if character =~ LITERAL_ENCODE
          hex = character.unpack('C*').map { |byte| '%02X' % byte }.join
          [character, '%'] + hex.chars + hex.downcase.chars
        else
          [character]
        end
      end.uniq
    end

    ##
    # The characters that nothing after an expression can contain, and the
    # final literal text, if it's written only one way, which the URI ends
    # with. Its characters are counted only where something else after the
    # expression can contain them, since the URI's last characters are left
    # for it.
    #
    # @param [Integer] index The expression's index.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Integer] first The index of the first literal text to count.
    #
    # @return [Array] The characters, and the final literal text or nil.
    def characters_after(index, expressions, literals, first = index + 1)
      suffixes = character_suffixes(expressions, literals)
      # Past the last literal text, there's none to count.
      texts = suffixes[:literals][first]
      key = [:after, expressions.object_id, literals.object_id,
             texts && texts.object_id,
             suffixes[:expressions][index + 1].object_id,
             first < literals.size]
      build_memo(key) do
        uncached_characters_after(index, expressions, literals, first)
      end
    end

    ##
    # Works out #characters_after.
    #
    # @param (see #characters_after)
    #
    # @return (see #characters_after)
    def uncached_characters_after(index, expressions, literals, first)
      later = literals[first..-1] || []
      final = later.last
      # A "#" can also be matched as "%23", so longer literal text with one
      # isn't written only one way. A single character is left as the URI's
      # last one either way.
      final = nil unless final && !final.empty? &&
        final.chars.all? { |c| TEXT_CHARACTERS.include?(c) } &&
        (final.size == 1 || !final.include?('#'))
      suffixes = character_suffixes(expressions, literals)
      characters = suffixes[:literals][first] || []
      characters |= literal_characters(later.last) if later.last && !final
      outside = TEXT_CHARACTERS - characters -
        (suffixes[:expressions][index + 1] || [])
      final = nil if final && (final.chars & outside).empty?
      [outside, final]
    end

    ##
    # The characters of the final literal text, as #characters_after gives
    # it.
    #
    # @param [String, nil] final The final literal text.
    #
    # @return [Array<String>]
    def final_characters(final)
      final ? final.chars.uniq : []
    end

    ##
    # For each index, the characters that the expressions from there to the
    # end can contain, and those of the literal text from there up to the
    # last one. They're worked out once while a template is built, since
    # each expression needs them.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    #
    # @return [Hash] The suffixes, as :expressions and :literals.
    def character_suffixes(expressions, literals)
      build_cached(:suffixes, expressions, literals) do
        # Where a set adds nothing, the one after it is kept, so that
        # positions with the same characters share one object.
        widen = lambda do |sets, characters|
          wider = characters | sets.first
          sets.unshift(wider.size == sets.first.size ? sets.first : wider)
        end
        after = [[]]
        expressions.reverse_each do |expression|
          widen.call(after, contained_characters(expression))
        end
        texts = [[]]
        literals[0...-1].reverse_each do |text|
          widen.call(texts, literal_characters(text))
        end
        { expressions: after, literals: texts }
      end
    end

    ##
    # The characters that the template's literal text or any of its
    # expressions can contain, worked out once while it's built.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    #
    # @return [Array<String>]
    def allowed_characters(expressions, literals)
      build_cached(:allowed, expressions, literals) do
        literals.join.chars | characters_in(expressions)
      end
    end

    ##
    # A value worked out once while a template is built, for the build's
    # own expressions and literals; outside a build, it's worked out each
    # time.
    #
    # @param [Symbol] kind What the value is.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals The pattern's literal text.
    #
    # @return [Object] The value.
    def build_cached(kind, expressions, literals)
      build_memo([kind, expressions.object_id, literals.object_id]) { yield }
    end

    ##
    # A value worked out once per key while a template is built; outside a
    # build, it's worked out each time. Long templates repeat the same
    # expression in the same surroundings, so the key is what the value
    # depends on, not the expression's index.
    #
    # @param [Array] key What the value depends on.
    #
    # @return [Object] The value.
    def build_memo(key)
      cache = Thread.current[BUILD_CACHE]
      return yield unless cache
      cache.fetch(key) { cache[key] = yield }
    end

    ##
    # The regexp source that takes every character of a set up to the last
    # one, possessively, leaving the URI's last characters for the final
    # literal text.
    #
    # @param [Array<String>] value The characters the value can contain.
    # @param [Array<String>] eaten The characters to take.
    # @param [String, nil] final The final literal text.
    # @param [Array<String>] endings Other regexp sources to take.
    #
    # @return [String] The source, empty if there's nothing to take.
    def take_through(value, eaten, final, endings = [])
      endings = endings.dup
      kept = eaten & final_characters(final)
      set = eaten - kept
      endings.unshift(character_set(set)) unless set.empty?
      unless kept.empty?
        taken = kept.size == 1 ? Regexp.escape(kept.first) : character_set(kept)
        before_final = final.size == 1 ? "(?!\\z)" : "(?=[\\s\\S]{#{final.size}})"
        endings << "#{taken}#{before_final}"
      end
      return "" if endings.empty?
      "(?:#{value_class(value - eaten)}*+(?:#{endings.join('|')}))*+"
    end

    ##
    # The sets of characters that decide how the last value of an expression
    # that literal text follows can skip the places where it can't end: the
    # characters it can contain, the final character, the literal text's
    # characters and its one character that nothing after it can contain,
    # the characters that reject the URI once the value has started, and
    # those it takes up front.
    #
    # @param [Integer] index The expression's index.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [String] group
    #   The regexp source for a character of the value, if not the
    #   operator's.
    #
    # @return [Hash, nil] The sets, or nil if the value doesn't skip any.
    def value_sets(index, expressions, literals, group = nil)
      _, operator, varlist = *expressions[index].match(EXPRESSION)
      return nil unless [nil, '+', '#', '/'].include?(operator)
      return nil if varlist.split(',').last[VARSPEC, 2] == '*'
      literal = literals[index + 1]
      return nil if literal.empty?
      group ||= operator == '+' || operator == '#' ? RESERVED : UNRESERVED
      after = characters_after(index, expressions, literals, index + 2)
      key = [:sets, expressions.object_id, literals.object_id, group,
             after.object_id, literal]
      build_memo(key) do
        sets_after(group, literal, after, expressions, literals)
      end
    end

    ##
    # Works out #value_sets once the expression is known to have them.
    #
    # @param [String] group The regexp source for a character of the value.
    # @param [String] literal The literal text after the expression.
    # @param [Array] after What #characters_after gives for the expression.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    #
    # @return [Hash, nil] The sets, or nil if the value doesn't skip any.
    def sets_after(group, literal, after, expressions, literals)
      value = group_characters(group)
      outside, final = after
      # The final character can end the URI, so only taking characters up
      # front may count it as one that nothing after can contain.
      strict = outside - final_characters(final)
      text = literal_characters(literal)
      # A character of the literal text that nothing after it can contain.
      last = text.size == 1 && literal.size == 1 && strict.include?(literal) ?
        literal : nil
      return nil if !last && !(text & strict).empty?
      # Characters that nothing in the template can contain are rejected
      # before matching.
      allowed = allowed_characters(expressions, literals)
      {
        value: value, final: final, text: text, last: last,
        guard: (strict - value - text) & allowed,
        # Characters of longer final literal text are rejected only before
        # the URI's last characters, which are left for it.
        final_guard: final && final.size > 1 ?
          ((outside & final_characters(final)) - value - text) & allowed : [],
        eaten: (outside & value) - text
      }
    end

    ##
    # Whether each expression's last value can start in only a few places,
    # so that looking ahead to the end of the URI from there costs linear
    # time in all. The expression starts a block and no earlier variable in
    # it is exploded, or literal text separates it from a lone variable that
    # can, and takes up front each character that would make this value
    # look ahead or take characters: this value then starts once where that
    # one is empty, and otherwise only after the last such character.
    #
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<Integer>] ends The expressions that end blocks.
    #
    # @return [Array<TrueClass, FalseClass>]
    def scanned_values(expressions, literals, ends)
      scans = []
      sets = Hash.new do |cache, index|
        cache[index] = value_sets(index, expressions, literals)
      end
      expressions.each_with_index do |expression, index|
        varspecs = expression[EXPRESSION, 2].split(',')
        if varspecs[0...-1].any? { |varspec| varspec[VARSPEC, 2] == '*' }
          scans << false
        elsif index == 0 || ends.include?(index - 1)
          scans << true
        else
          previous = expressions[index - 1][EXPRESSION, 2]
          before = scans[index - 1] && !literals[index].empty? &&
            previous =~ VARSPEC && $2 != '*' &&
            sets[index - 1]
          after = sets[index]
          scans << (before && after ?
            ((after[:guard] | after[:eaten]) - before[:eaten]).empty? : false)
        end
      end
      scans
    end

    ##
    # The regexp source for the last value of an expression that literal
    # text follows, which tries the same values, in the same order, as the
    # plain one, but skips those that can't let the rest of the URI match:
    #
    # * Nothing after the literal text can contain some characters, so the
    #   value takes each of them that it can, up to the last one, and the
    #   URI is rejected if it has one that the value can't take. When the
    #   literal text is one such character, the value takes everything up to
    #   the last place where it's written as it is.
    # * After those, the next expression can take any characters that the
    #   value could, and the literal text, up to a character that it can't.
    #   Until then, the literal text's first place is the only one tried,
    #   since if the rest doesn't match from there, it doesn't from a later
    #   place either.
    #
    # Without this, a URI that doesn't match would be tried with the value
    # ending at every place where the literal text is, matching the rest
    # again each time, which takes polynomial time on engines that don't
    # memoize (MRI < 3.3, JRuby and TruffleRuby).
    #
    # @param [Integer] index The expression's index.
    # @param [Array<String>] expressions The pattern's expressions.
    # @param [Array<String>] literals
    #   The literal text before each expression, and after the last one.
    # @param [Array<String>] literal_sources The regexp source of each literal.
    # @param [Array<TrueClass, FalseClass>] empties
    #   Whether each expression only matches nothing.
    # @param [String] group
    #   The regexp source for a character of the value, if not the
    #   operator's.
    # @param [TrueClass, FalseClass] scan
    #   Whether the value can start in only a few places, so that looking
    #   ahead to the end of the URI from there costs linear time in all.
    #
    # @return [String, nil] The source, or nil if the plain one is used.
    def bounded_value(index, expressions, literals, literal_sources, empties,
                      group = nil, scan = true)
      sets = value_sets(index, expressions, literals, group)
      return nil unless sets
      following = (index + 1...expressions.size).find { |later| !empties[later] }
      # The expression that follows directly, past any that only match
      # nothing, if only empty literal text comes before it.
      next_expression = following &&
        literals[(index + 2)..following].all?(&:empty?) &&
        expressions[following]
      key = [:bounded, sets.object_id, scan, next_expression,
             literal_sources[index + 1]]
      build_memo(key) do
        bounded_source(sets, scan, next_expression, literal_sources[index + 1])
      end
    end

    ##
    # Works out #bounded_value from the expression's value sets.
    #
    # @param [Hash] sets What #value_sets gives for the expression.
    # @param [TrueClass, FalseClass] scan See #bounded_value.
    # @param [String, nil] next_expression
    #   The expression that follows directly, or nil if none does.
    # @param [String] literal_source The regexp source of the literal text.
    #
    # @return [String] The source.
    def bounded_source(sets, scan, next_expression, literal_source)
      value, final, text, last, guard, eaten, final_guard =
        sets.values_at(:value, :final, :text, :last, :guard, :eaten,
                       :final_guard)
      unless scan
        # Only the literal text's first place in each stretch is tried.
        final = last = nil
        guard = eaten = final_guard = []
      end
      source = "".dup
      if !final_guard.empty?
        source << "(?=#{character_set(guard | final_guard, true)}*+" \
          "[\\s\\S]{0,#{final.size}}\\z)"
      elsif !guard.empty?
        source << "(?=#{character_set(guard, true)}*+\\z)"
      end
      repeated = last && value.include?(last)
      rest = value - eaten - [last]
      escaped = Regexp.escape(last) if last
      endings = repeated ? ["#{escaped}(?=[^#{escaped}]*#{escaped})"] : []
      source << take_through(value - [last], eaten, final, endings)
      # Nothing after the literal text can contain its character, so the
      # literal text is at or after the last place where it's written as it
      # is.
      source << "(?:#{value_class(rest)}*+(?=#{escaped}))?+" if last
      tail = value - eaten - [last]
      if repeated
        # The value ends before the last one, or takes it, and the literal
        # text is pct-encoded after it.
        source << "(?:#{escaped}#{take_through(value - [last], eaten, final)})??"
      end
      if next_expression &&
          !last && (text - absorbed(next_expression, text)).empty?
        stops = tail - absorbed(next_expression, tail)
        within = value_class(tail - stops)
        first = "(?>#{within}*?(?=#{literal_source}))"
        source << (stops.empty? ? first :
          "(?:(?>#{within}*+#{character_set(stops)}))*?#{first}")
      else
        source << "#{value_class(tail)}*?"
      end
      source
    end

    ##
    # Generates the <tt>Regexp</tt> that parses a template pattern.
    #
    # Where it's known whether the regular expression engine matches a
    # regexp in linear time (MRI 3.2 and later, TruffleRuby), the one that keeps
    # every choice open is used when it does, since the engine then can't
    # backtrack catastrophically, and its rewrites to commit to choices
    # could keep the engine from matching in linear time. Both give the same
    # values.
    #
    # @param [String] pattern The URI template pattern.
    # @param [#match] processor The template processor to use.
    # @param [Array<Array>] patterns
    #   The processor's pattern for each variable, if already known.
    # @param [TrueClass, FalseClass] commit
    #   Whether to commit to choices, if not decided by the patterns.
    #
    # @return [Array, Regexp]
    #   An array of expansion variables nad a regular expression which may be
    #   used to parse a template pattern
    def parse_new_template_pattern(pattern, processor = nil, patterns = nil,
                                   commit = nil)
      # Values that several steps need for each expression are worked
      # out once per build, in a cache only this thread sees.
      owner = Thread.current[BUILD_CACHE].nil?
      Thread.current[BUILD_CACHE] = {} if owner
      escaped_pattern, raw_expressions, literals, literal_sources,
        either_leader, either_literal = template_parts(pattern)
      dotted_labels = raw_expressions.each_index.map do |index|
        label_takes_dots?(
          index, raw_expressions, literals, either_leader, either_literal
        )
      end

      expansions = []
      # How many expressions name each variable.
      naming = Hash.new(0)
      raw_expressions.each do |expression|
        expression[EXPRESSION, 2].split(',').map do |varspec|
          varspec[VARSPEC, 1]
        end.uniq.each { |name| naming[name] += 1 }
      end
      # Processor patterns can match anything, so they get 2.9.0's choices.
      plain_processor = !(processor && processor.respond_to?(:match))
      followers = expression_followers(escaped_pattern)
      patterns ||= raw_expressions.map do |expansion|
        expansion[EXPRESSION, 2].split(',').map do |varspec|
          plain_processor ? nil : processor.match(varspec[VARSPEC, 1])
        end
      end
      # Where a processor gives a variable its own pattern, the choices
      # before it can't be judged from the operators, so every choice is
      # kept open, as in 2.9.0.
      commit = !patterns.flatten.any? if commit.nil?
      # Where the engine matches the regexp that keeps every choice open in
      # linear time, it's used, since committing can keep the engine from
      # doing so.
      if commit && LINEAR_TIME_CHECKED
        open = parse_new_template_pattern(pattern, processor, patterns, false)
        return open if linear_time?(open[1])
      end
      # Whether each expression only matches nothing, because the one after
      # it takes whatever it could.
      empties = raw_expressions.each_index.map do |index|
        following = followers[index].first
        _, operator, varlist = *raw_expressions[index].match(EXPRESSION)
        plain_processor && following &&
          absorbed_by?(following, operator, varlist.split(',')) ? true : false
      end
      ends = commit ? block_ends(raw_expressions, literals, empties) : []
      scans = commit ? scanned_values(raw_expressions, literals, ends) : []

      # Create a regular expression that captures the values of the
      # variables in the URI.
      expression_sources = raw_expressions.map do |expansion|
        index = expansions.size
        expansions << expansion
        _, operator, varlist = *expansion.match(EXPRESSION)
        leader = Regexp.escape(LEADERS.fetch(operator, ''))
        if operator == '#' && either_leader[index]
          leader = NUMBER_SIGN_EITHER_FORM
        end
        joiner = Regexp.escape(JOINERS.fetch(operator, ','))
        varspecs = varlist.split(',')
        results = patterns[index]
        # A ;, ? or & variable that isn't exploded is written as its own
        # name, so a pair in its place can only have the name of one of the
        # expression's variables that aren't exploded. Matching gives each
        # pair to its variable afterwards.
        named = NAMED_OPERATORS.include?(operator) &&
          named_pair_source(operator, varspecs, results)
        # Without processor patterns, any variable in the expression can take
        # the characters that an earlier variable leaves, which lets the
        # variables after the first one have fewer choices below.
        plain = results.compact.empty?
        explodes = varspecs.map { |varspec| varspec[VARSPEC, 2] == '*' }
        first_explode = explodes.index(true)
        scan = scans[index]
        # A name used in another expression too takes the first value it's
        # given, so a choice skipped below might be the one that gives the
        # value it gets.
        shared = varspecs.any? do |varspec|
          naming[varspec[VARSPEC, 1]] > 1
        end
        first_named = explodes.index(false)
        not_after_value =
          "(?<![#{Addressable::URI::CharacterClasses::UNRESERVED}])" \
          "(?<![^\\x00-\\x7F])"
        # A lookahead that skips the expression's empty choice where it
        # can't lead to a match.
        empty_guard = nil
        combined = varspecs.each_with_index.map do |varspec, position|
          _, name, modifier = *varspec.match(VARSPEC)
          name = capture_name(name)

          if named && modifier != '*'
            # The pairs of the variables that aren't exploded are matched
            # as one run, in any order, by the first of them, so each name
            # is written once however many variables the expression has.
            # The others match nothing, and matching gives each pair to its
            # variable afterwards.
            if position == first_named
              next "(?<#{name}>#{named}(?:#{joiner}#{named})*)?"
            else
              next "(?<#{name}>)"
            end
          end

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
                bounded = commit && position == varspecs.size - 1 &&
                  bounded_value(index, raw_expressions, literals,
                                literal_sources, empties, RESERVED_NO_COMMA,
                                scan)
                "(?<#{name}>#{bounded || "#{RESERVED_NO_COMMA}*?"})?"
              else
                # 2.9.0 skipped the variable when it couldn't be empty.
                "(?:(?<#{name}>)(?!#{RESERVED_NO_COMMA}))?"
              end
            elsif plain && modifier == '*' && explodes[(position + 1)..-1].any? &&
                (operator.nil? || operator == '/' || operator == '.') &&
                !may_follow_with?(index, JOINERS.fetch(operator, ','),
                                  raw_expressions, literals)
              # Exploded values were tried shortest first, and a later
              # exploded variable can match whatever this one leaves, so once
              # a split fails, every split where this variable is longer
              # fails too. Of the values tried, only the leading joiners are
              # shorter than every value tried before them. It takes every
              # leading joiner, so that they aren't divided with the later
              # variables. That's only when what follows the expression can't
              # start with a joiner, which would end it earlier. Giving one
              # back never helps then, so where choices are kept open, the
              # joiners are taken greedily instead, which an engine that
              # matches in linear time can do without backtracking.
              "(?<#{name}>(?:#{joiner})*#{commit ? '+' : ''})"
            elsif plain && modifier == '*' && position < varspecs.size - 1 &&
                explodes.count(true) == 1 &&
                (operator.nil? || operator == '/' || operator == '.')
              # The later variables can't contain a joiner, so this takes
              # whole members that a joiner ends, fewest first, and the later
              # variables divide what's after them. A run of characters
              # without a joiner isn't divided two ways.
              "(?<#{name}>(?:#{group}#{joiner})*?)"
            elsif plain && explodes[0...position].any? && !shared &&
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
            elsif commit && modifier == '*' &&
                position == varspecs.size - 1 &&
                (operator == '+' || operator == '#') &&
                members_follow?(index, raw_expressions, literals)
              # Each member takes every character it can, so the value can
              # only end before a comma, a character it can't contain or the
              # end of the URI, and never before what follows it.
              "(?<#{name}>(?!))?"
            elsif modifier == '*'
              through = ""
              if commit && plain && scan && varspecs.size == 1 &&
                  literals[index + 1].empty? &&
                  index < raw_expressions.size - 1 &&
                  [nil, '/', '.', '+', '#'].include?(operator)
                # Another expression follows the value directly, and nothing
                # after it can contain some characters the value can, so it
                # takes each of them up to the last one first. Without this,
                # the later expressions would divide the text before the
                # last one in every way first.
                member = if operator == '+' || operator == '#'
                  RESERVED_NO_COMMA
                else
                  group.sub(/\*[?+]\z/, '')
                end
                characters = group_characters(member) |
                  [JOINERS.fetch(operator, ',')]
                outside, final =
                  characters_after(index, raw_expressions, literals)
                through = take_through(
                  characters, characters & outside, final
                )
                # Without the value, nothing could take them.
                kept = final_characters(final)
                taken = characters & outside
                unless taken.empty?
                  rest = final && !(taken & kept).empty? ?
                    "[\\s\\S]{0,#{final.size}}" : ""
                  empty_guard = "(?=#{character_set(taken, true)}*+#{rest}\\z)"
                end
              end
              "(?<#{name}>#{through}#{value})?"
            elsif varspecs.size > 1 && (operator == '+' || operator == '#') &&
                  position < varspecs.size - 1
              "(?<#{name}>#{RESERVED_NO_COMMA}*+)?"
            elsif plain && position < varspecs.size - 1 &&
                  (operator.nil? || operator == '/' || operator == '.')
              # Values were tried shortest first, so a run of characters
              # without a joiner went to a later variable. The only other
              # value that could change the result is the whole run up to the
              # next joiner.
              "(?<#{name}>(?:#{group}(?=#{joiner}))??)"
            elsif commit && position == varspecs.size - 1 &&
                (bounded = bounded_value(index, raw_expressions, literals,
                                         literal_sources, empties, nil, scan))
              "(?<#{name}>#{bounded})?"
            else
              "(?<#{name}>#{group})?"
            end
          end
        end
        following, comma_follows = followers[index]
        single = varspecs.size == 1 && varspecs.first[VARSPEC, 2] != '*'
        last_group = case operator
                     when '+', '#' then "#{RESERVED}*?"
                     when nil, '/' then "#{UNRESERVED}*?"
                     when '.'
                       "#{UNRESERVED.gsub('\.', '')}*?" unless dotted_labels[index]
                     end
        if commit && plain && last_group && following &&
            following[1].nil? && varspecs.last[VARSPEC, 2] != '*'
          # Values were tried shortest first, and the next expression can
          # take any run of unreserved characters at its start, and of
          # commas too if it has an exploded variable, so the last value
          # only needs to end after a character that the next expression
          # couldn't take.
          no_comma = following[2].include?('*') ? "(?<!,)" : ""
          # Nothing after the value can contain some characters, so it
          # takes each of them up to the last one first.
          value_characters = group_characters(last_group.chomp('*?'))
          outside, final = characters_after(index, raw_expressions, literals)
          through = scan ? take_through(
            value_characters, value_characters & outside, final
          ) : ""
          combined[-1] = "(?<#{capture_name(varspecs.last[VARSPEC, 1])}>" \
            "|#{through}#{last_group}#{not_after_value}#{no_comma})?"
        end
        if empties[index]
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
            varspecs.none? { |varspec| varspec[VARSPEC, 2] == '*' }
          # 2.9.0 tried each value with the joiner after it first, then the
          # value on its own, then skipping the variable, and every other
          # choice gave a value to a later variable that an earlier one had
          # already been tried with. A variable after a skipped one is
          # skipped too. Stopping before a joiner is left out, so this is only
          # used when no joiner can follow the expression.
          nested = varspecs[0...-1].reverse.inject("") do |inner, varspec|
            "(?:(?<#{capture_name(varspec[VARSPEC, 1])}>" \
              "#{RESERVED_NO_COMMA}*+)" \
              "#{joiner}?+#{inner}|(?=#{RESERVED_NO_COMMA}))"
          end
          combined = nested + combined.last
        else
          combined = combined.join("#{joiner}?")
        end
        "(?:#{empty_guard}|#{leader}#{combined})"
      end

      regexp_string = assemble_regexp(
        raw_expressions, literals, literal_sources, expression_sources,
        empties, commit, ends
      )
      return expansions, Regexp.new(regexp_string), patterns
    ensure
      Thread.current[BUILD_CACHE] = nil if owner
    end

    # MRI 3.2 memoizes a match, so that it takes linear time, unless the
    # regexp has a lookaround, an atomic group, a possessive quantifier or a
    # backreference, but can't say so. Later versions and TruffleRuby can.
    MEMOIZES_WITHOUT_LOOKAROUNDS =
      RUBY_ENGINE == 'ruby' && RUBY_VERSION.start_with?('3.2.')
    UNMEMOIZED = /\(\?(?:[=!>]|<[=!])|[*+?}]\+|\\[1-9k]/
    LINEAR_TIME_CHECKED =
      Regexp.respond_to?(:linear_time?) || MEMOIZES_WITHOUT_LOOKAROUNDS
    private_constant :MEMOIZES_WITHOUT_LOOKAROUNDS, :UNMEMOIZED,
      :LINEAR_TIME_CHECKED

    ##
    # Whether the regular expression engine matches a regexp in linear time.
    #
    # @param [Regexp] regexp The regexp.
    #
    # @return [TrueClass, FalseClass]
    def linear_time?(regexp)
      if Regexp.respond_to?(:linear_time?)
        Regexp.linear_time?(regexp)
      else
        regexp.source !~ UNMEMOIZED
      end
    end

  end
end
