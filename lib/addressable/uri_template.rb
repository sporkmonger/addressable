# encoding:utf-8
#--
# Copyright (C) 2006-2011 Bob Aman
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


require "addressable/version"
require "addressable/uri"
require "addressable/template"

module Addressable
  ##
  # This is an implementation of a URI template based on
  # <a href="http://tinyurl.com/uritemplatedraft03">URI Template draft 03</a>.
  class UriTemplate < Template
    # Constants used throughout the template code.
    anything =
      Addressable::URI::CharacterClasses::RESERVED +
      Addressable::URI::CharacterClasses::UNRESERVED


    variable_char_class =
      Addressable::URI::CharacterClasses::ALPHA +
      Addressable::URI::CharacterClasses::DIGIT + ?_

    var_char =
      "(?:(?:[#{variable_char_class}]|%[a-fA-F0-9][a-fA-F0-9])+)"
    RESERVED =
      "(?:[#{anything}]|%[a-fA-F0-9][a-fA-F0-9])"
    UNRESERVED =
      "(?:[#{
        Addressable::URI::CharacterClasses::UNRESERVED
      }]|%[a-fA-F0-9][a-fA-F0-9])"
    variable =
      "(?:#{var_char}(?:\\.?#{var_char})*)"
    varspec =
      "(?:(#{variable})(\\*|:\\d+)?)"
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


    OPERATOR_EXPANSION =
      /\{-([a-zA-Z]+)\|([#{anything}]+)\|([#{anything}]+)\}/
    VARIABLE_EXPANSION = /\{([#{anything}]+?)(?:=([#{anything}]+))?\}/


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
    #     "http://example.com/{first}/{second}/"
    #   ).match(uri, ExampleProcessor)
    #   match.variables
    #   #=> ["first", "second"]
    #   match.captures
    #   #=> ["a", "b/c"]
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   match = Addressable::Template.new(
    #     "http://example.com/{first}/{-list|/|second}/"
    #   ).match(uri)
    #   match.variables
    #   #=> ["first", "second"]
    #   match.captures
    #   #=> ["a", ["b", "c"]]
    def match(uri, processor=nil)
      uri = Addressable::URI.parse(uri)
      mapping = {}

      # First, we need to process the pattern, and extract the values.
      expansions, expansion_regexp =
        parse_template_pattern(pattern, processor)
      unparsed_values = uri.to_str.scan(expansion_regexp).flatten

      if uri.to_str == pattern
        return Addressable::Template::MatchData.new(uri, self, mapping)
      elsif expansions.size > 0
        index = 0
        expansions.each do |expansion|
          _, operator, varlist = *expansion.match(EXPRESSION)
          case operator
          when nil, ?+, ?#, ?/, ?.
            varlist.split(',').each do |varspec|
              unparsed_value = unparsed_values[index]
              name = varspec[VARSPEC, 1]
              value = unparsed_value
              if processor != nil && processor.respond_to?(:restore)
                value = processor.restore(name, value)
              end
              if processor == nil && !%w(+ #).include?(operator)
                value = Addressable::URI.unencode_component(value)
              end
              if mapping[name] == nil || mapping[name] == value
                mapping[name] = value
              else
                return nil
              end
              index = index + 1
            end
          when ?;, ??, ?&
            varlist.split(',').each do |varspec|
              name, value = unparsed_values[index].split('=')
              value = "" if value.nil?
              if processor != nil && processor.respond_to?(:restore)
                value = processor.restore(name, value)
              end
              if processor == nil
                value = Addressable::URI.unencode_component(value)
              end
              if mapping[name] == nil || mapping[name] == value
                mapping[name] = value
              else
                return nil
              end
              index = index + 1
            end
          end
          # if expansion =~ OPERATOR_EXPANSION
            # operator, argument, variables =
              # parse_template_expansion(expansion)
            # extract_method = "extract_#{operator}_operator"
            # if ([extract_method, extract_method.to_sym] &
                # private_methods).empty?
              # raise InvalidTemplateOperatorError,
                # "Invalid template operator: #{operator}"
            # else
              # begin
                # send(
                  # extract_method.to_sym, unparsed_value, processor,
                  # argument, variables, mapping
                # )
              # rescue TemplateOperatorAbortedError
                # return nil
              # end
            # end
          # else
        end
        return Addressable::Template::MatchData.new(uri, self, mapping)
      else
        return nil
      end
    end

    ##
    # Expands a URI template into another URI template.
    #
    # @param [Hash] mapping The mapping that corresponds to the pattern.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
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
    # @return [Addressable::Template] The partially expanded URI template.
    #
    # @example
    #   Addressable::Template.new(
    #     "http://example.com/{one}/{two}/"
    #   ).partial_expand({"one" => "1"}).pattern
    #   #=> "http://example.com/1/{two}/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/search/{-list|+|query}/"
    #   ).partial_expand(
    #     {"query" => "an example search query".split(" ")}
    #   ).pattern
    #   #=> "http://example.com/search/an+example+search+query/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/{-join|&|one,two}/"
    #   ).partial_expand({"one" => "1"}).pattern
    #   #=> "http://example.com/?one=1{-prefix|&two=|two}"
    #
    #   Addressable::Template.new(
    #     "http://example.com/{-join|&|one,two,three}/"
    #   ).partial_expand({"one" => "1", "three" => 3}).pattern
    #   #=> "http://example.com/?one=1{-prefix|&two=|two}&three=3"
    def partial_expand(mapping, processor=nil)
      result = self.pattern.dup
      result.gsub!( EXPRESSION ) do |capture|
        _, operator, varlist = *capture.match(EXPRESSION)
        case operator
        when nil
          name = varlist[VARSPEC, 1]
          val = mapping[name]
          if val
            transform_mapped(val, processor)
          else
            capture
          end
        end
      end
      return Addressable::Template.new(result)
    end

    ##
    # Expands a URI template into a full URI.
    #
    # @param [Hash] mapping The mapping that corresponds to the pattern.
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
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
    #     "http://example.com/search/{-list|+|query}/"
    #   ).expand(
    #     {"query" => "an example search query".split(" ")}
    #   ).to_str
    #   #=> "http://example.com/search/an+example+search+query/"
    #
    #   Addressable::Template.new(
    #     "http://example.com/search/{query}/"
    #   ).expand(
    #     {"query" => "bogus!"},
    #     ExampleProcessor
    #   ).to_str
    #   #=> Addressable::Template::InvalidTemplateValueError
    def expand(mapping, processor=nil)
      result = self.pattern.dup
      mapping = normalize_keys(mapping)
      result.gsub!( EXPRESSION ) do |capture|
        transform_capture(mapping, capture, processor)

        # if capture =~ OPERATOR_EXPANSION
          # operator, argument, variables, default_mapping =
            # parse_template_expansion(capture, transformed_mapping)
          # expand_method = "expand_#{operator}_operator"
          # if ([expand_method, expand_method.to_sym] & private_methods).empty?
            # raise InvalidTemplateOperatorError,
              # "Invalid template operator: #{operator}"
          # else
            # send(expand_method.to_sym, argument, variables, default_mapping)
          # end
        # else
          # varname, _, vardefault = capture.scan(/^\{(.+?)(=(.*))?\}$/)[0]
          # transformed_mapping[varname] || vardefault
        # end
      end
      return Addressable::URI.parse(result)
    end


  private
    def ordered_variable_defaults
      @ordered_variable_defaults ||= (
        expansions, expansion_regexp = parse_template_pattern(pattern)
        expansions.map do |capture|
          _, operator, varlist = *capture.match(EXPRESSION)
          varlist.split(',').map do |varspec|
            name = varspec[VARSPEC, 1]
          end
        end.flatten
      )
    end

    ##
    # Transforms a mapped value so that values can be substituted into the
    # template.
    #
    # @param [Object] mapped A value to map
    # @param [Boolean] allow_reserved Allow reserved charaters?
    #   Defaults to false
    # @param [#validate, #transform] processor
    #   An optional processor object may be supplied.
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
    # @return [Object] The transformed mapped value
    def transform_capture(mapping, capture, processor=nil)
      _, operator, varlist = *capture.match(EXPRESSION)
      return_value = varlist.split(',').inject({}) do |acc, varspec|
        name = varspec[VARSPEC, 1]
        value = mapping[name]
        allow_reserved = %w(+ #).include?(operator)
        value = value.to_s if Numeric === value || Symbol === value

        unless value.respond_to?(:to_ary) || value.respond_to?(:to_str)
          raise TypeError,
            "Can't convert #{value.class} into String or Array."
        end

        value = value.respond_to?(:to_ary) ? value.to_ary : value.to_str

        # Handle unicode normalization
        if value.kind_of?(Array)
          value.map! { |val| Addressable::IDNA.unicode_normalize_kc(val) }
        else
          value = Addressable::IDNA.unicode_normalize_kc(value)
        end

        if processor == nil || !processor.respond_to?(:transform)
          # Handle percent escaping
          if allow_reserved
            encode_map =
              Addressable::URI::CharacterClasses::RESERVED +
              Addressable::URI::CharacterClasses::UNRESERVED
          else
            encode_map = Addressable::URI::CharacterClasses::UNRESERVED
          end
          if value.kind_of?(Array)
            transformed_value = value.map do |val|
              Addressable::URI.encode_component( val, encode_map)
            end
          else
            transformed_value = Addressable::URI.encode_component(
              value, encode_map)
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
            if transformed_value.kind_of?(Array)
              transformed_value.map! do |val|
                Addressable::IDNA.unicode_normalize_kc(val)
              end
            else
              transformed_value =
                Addressable::IDNA.unicode_normalize_kc(transformed_value)
            end
          end
        end
        acc[name] = transformed_value
        acc
      end
      case operator
      when ?.
        ?. + return_value.values.join('.')
      when ?/
        ?/ + return_value.values.join('/')
      when ?#
        ?# + return_value.values.join(',')
      when ?&
        ?& + return_value.map{|k,v|
          "#{k}=#{v}"
        }.join('&')
      when ??
        ?? + return_value.map{|k,v|
          "#{k}=#{v}"
        }.join('&')
      when ?;
        return_value.map{|k,v|
          v && v != '' ?  ";#{k}=#{v}" : ";#{k}"
        }.join
      else
        return_value.values.join(',')
      end
    end


    ##
    # Generates a hash with string keys
    #
    # @param [Hash] mapping A mapping hash to normalize
    #
    # @return [Hash]
    #   A hash with stringified keys
    def normalize_keys(mapping)
      return mapping.inject({}) do |accu, pair|
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
    # Generates the <tt>Regexp</tt> that parses a template pattern.
    #
    # @param [String] pattern The URI template pattern.
    # @param [#match] processor The template processor to use.
    #
    # @return [Regexp]
    #   A regular expression which may be used to parse a template pattern.
    def parse_template_pattern(pattern, processor=nil)
      # Escape the pattern. The two gsubs restore the escaped curly braces
      # back to their original form. Basically, escape everything that isn't
      # within an expansion.
      escaped_pattern = Regexp.escape(
        pattern
      ).gsub(/\\\{(.*?)\\\}/) do |escaped|
        escaped.gsub(/\\(.)/, "\\1")
      end

      expansions = []

      # Create a regular expression that captures the values of the
      # variables in the URI.
      regexp_string = escaped_pattern.gsub( EXPRESSION ) do |expansion|

        expansions << expansion
        _, operator, varlist = *expansion.match(EXPRESSION)
        case operator
        when ?+
          varlist.split(',').map do |varspec|
            "(#{ RESERVED }*?)"
          end.join(',')
        when ?#
          ?# + varlist.split(',').map do |varspec|
            "(#{ RESERVED }*?)"
          end.join(',')
        when ?/
          varlist.split(',').map do |varspec|
            "(#{ UNRESERVED }*?)"
          end.join('/?')
        when ?.
          '\.' + varlist.split(',').map do |varspec|
            "(#{ UNRESERVED.gsub('\.', '') }*?)"
          end.join('\.?')
        when ?;
          ?; + varlist.split(',').map do |varspec|
            "(#{ UNRESERVED }*=?#{ UNRESERVED }*?)"
          end.join(';?')
        when ??
          '\?' + varlist.split(',').map do |varspec|
            "(#{ UNRESERVED }*=#{ UNRESERVED }*?)"
          end.join('&')
        when ?&
          '&' + varlist.split(',').map do |varspec|
            "(#{ UNRESERVED }*=#{ UNRESERVED }*?)"
          end.join('&')
        else
          varlist.split(',').map do |varspec|
            "(#{ UNRESERVED }*?)"
          end.join(',')
        end
      end

      # Ensure that the regular expression matches the whole URI.
      regexp_string = "^#{regexp_string}$"
      return expansions, Regexp.new(regexp_string)
    end

  end
end
