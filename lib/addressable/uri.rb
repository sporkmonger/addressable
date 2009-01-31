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
    # Raised if an invalid template value is supplied.
    class InvalidTemplateValueError < StandardError
    end

    ##
    # Raised if an invalid template operator is used in a pattern.
    class InvalidTemplateOperatorError < StandardError
    end

    ##
    # Raised if an invalid template operator is used in a pattern.
    class TemplateOperatorAbortedError < StandardError
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
    #   <tt>false</tt> otherwise.  An <tt>InvalidTemplateValueError</tt>
    #   exception will be raised if the value is invalid.  The
    #   <tt>transform</tt> method should return the transformed variable
    #   value as a <tt>String</tt>.  If a <tt>transform</tt> method is used,
    #   the value will not be percent encoded automatically.  Unicode
    #   normalization will be performed both before and after sending the
    #   value to the transform method.
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
    #     "http://example.com/search/{-list|+|query}/",
    #     {"query" => "an example search query".split(" ")}
    #   ).to_s
    #   #=> "http://example.com/search/an+example+search+query/"
    #
    #   Addressable::URI.expand_template(
    #     "http://example.com/search/{query}/",
    #     {"query" => "bogus!"},
    #     ExampleProcessor
    #   ).to_s
    #   #=> Addressable::URI::InvalidTemplateValueError
    def self.expand_template(pattern, mapping, processor=nil)

      # FIXME: MUST REFACTOR!!!

      result = pattern.dup

      reserved = Addressable::URI::CharacterClasses::RESERVED
      unreserved = Addressable::URI::CharacterClasses::UNRESERVED
      anything = reserved + unreserved
      operator_expansion =
        /\{-([a-zA-Z]+)\|([#{anything}]+)\|([#{anything}]+)\}/
      variable_expansion = /\{([#{anything}]+?)(=([#{anything}]+))?\}/

      transformed_mapping = mapping.inject({}) do |accu, pair|
        name, value = pair
        unless value.respond_to?(:to_ary) || value.respond_to?(:to_str)
          raise TypeError,
            "Can't convert #{value.class} into String or Array."
        end

        value =
          value.respond_to?(:to_ary) ? value.to_ary : value.to_str
        # Handle unicode normalization
        if value.kind_of?(Array)
          value.map! { |val| Addressable::IDNA.unicode_normalize_kc(val) }
        else
          value = Addressable::IDNA.unicode_normalize_kc(value)
        end

        if processor == nil || !processor.respond_to?(:transform)
          # Handle percent escaping
          if value.kind_of?(Array)
            transformed_value = value.map do |val|
              self.encode_component(
                val, Addressable::URI::CharacterClasses::UNRESERVED)
            end
          else
            transformed_value = self.encode_component(
              value, Addressable::URI::CharacterClasses::UNRESERVED)
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

        accu[name] = transformed_value
        accu
      end
      result.gsub!(
        /#{operator_expansion}|#{variable_expansion}/
      ) do |capture|
        if capture =~ operator_expansion
          operator, argument, variables, default_mapping =
            parse_template_expansion(capture, transformed_mapping)
          expand_method = "expand_#{operator}_operator"
          if ([expand_method, expand_method.to_sym] & private_methods).empty?
            raise InvalidTemplateOperatorError,
              "Invalid template operator: #{operator}"
          else
            send(expand_method.to_sym, argument, variables, default_mapping)
          end
        else
          varname, _, vardefault = capture.scan(/^\{(.+?)(=(.*))?\}$/)[0]
          transformed_mapping[varname] || vardefault
        end
      end
      return Addressable::URI.parse(result)
    end

    ##
    # Expands a URI Template opt operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_opt_operator(argument, variables, mapping)
      if (variables.any? do |variable|
        mapping[variable] != [] &&
        mapping[variable]
      end)
        argument
      else
        ""
      end
    end
    class <<self; private :expand_opt_operator; end

    ##
    # Expands a URI Template neg operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_neg_operator(argument, variables, mapping)
      if (variables.any? do |variable|
        mapping[variable] != [] &&
        mapping[variable]
      end)
        ""
      else
        argument
      end
    end
    class <<self; private :expand_neg_operator; end

    ##
    # Expands a URI Template prefix operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_prefix_operator(argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'prefix' takes exactly one variable."
      end
      value = mapping[variables.first]
      if value.kind_of?(Array)
        (value.map { |list_value| argument + list_value }).join("")
      else
        argument + value.to_s
      end
    end
    class <<self; private :expand_prefix_operator; end

    ##
    # Expands a URI Template suffix operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_suffix_operator(argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'suffix' takes exactly one variable."
      end
      value = mapping[variables.first]
      if value.kind_of?(Array)
        (value.map { |list_value| list_value + argument }).join("")
      else
        value.to_s + argument
      end
    end
    class <<self; private :expand_suffix_operator; end

    ##
    # Expands a URI Template join operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_join_operator(argument, variables, mapping)
      variable_values = variables.inject([]) do |accu, variable|
        if !mapping[variable].kind_of?(Array)
          if mapping[variable]
            accu << variable + "=" + (mapping[variable])
          end
        else
          raise InvalidTemplateOperatorError,
            "Template operator 'join' does not accept Array values."
        end
        accu
      end
      variable_values.join(argument)
    end
    class <<self; private :expand_join_operator; end

    ##
    # Expands a URI Template list operator.
    #
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The expanded result.
    def self.expand_list_operator(argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'list' takes exactly one variable."
      end
      mapping[variables.first].join(argument)
    end
    class <<self; private :expand_list_operator; end

    ##
    # Parses a URI template expansion <tt>String</tt>.
    #
    # @param [String] expansion The operator <tt>String</tt>.
    # @param [Hash] mapping The mapping to merge defaults into.
    #
    # @return [Array]
    #   A tuple of the operator, argument, variables, and mapping.
    def self.parse_template_expansion(capture, mapping)
      operator, argument, variables = capture[1...-1].split("|")
      operator.gsub!(/^\-/, "")
      variables = variables.split(",")
      mapping = (variables.inject({}) do |accu, var|
        varname, _, vardefault = var.scan(/^(.+?)(=(.*))?$/)[0]
        accu[varname] = vardefault
        accu
      end).merge(mapping)
      variables = variables.map { |var| var.gsub(/=.*$/, "") }
      return operator, argument, variables, mapping
    end
    class <<self; private :parse_template_expansion; end

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
    #   The <tt>match</tt> method should return a <tt>String</tt> containing
    #   a regular expression capture group for matching on that particular
    #   variable.  The default value is ".*?".  The <tt>match</tt> method has
    #   no effect on multivariate operator expansions.
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
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   uri.extract_mapping(
    #     "http://example.com/{first}/{second}/",
    #     ExampleProcessor
    #   )
    #   #=> {"first" => "a", "second" => "b/c"}
    #
    #   uri = Addressable::URI.parse("http://example.com/a/b/c/")
    #   uri.extract_mapping(
    #     "http://example.com/{first}/{-list|/|second}/"
    #   )
    #   #=> {"first" => "a", "second" => ["b", "c"]}
    def extract_mapping(pattern, processor=nil)
      reserved = Addressable::URI::CharacterClasses::RESERVED
      unreserved = Addressable::URI::CharacterClasses::UNRESERVED
      anything = reserved + unreserved
      operator_expansion =
        /\{-([a-zA-Z]+)\|([#{anything}]+)\|([#{anything}]+)\}/
      variable_expansion = /\{([#{anything}]+?)(=([#{anything}]+))?\}/

      # First, we need to process the pattern, and extract the values.
      expansions, expansion_regexp =
        parse_template_pattern(pattern, processor)
      unparsed_values = self.to_s.scan(expansion_regexp).flatten

      mapping = {}

      if self.to_s == pattern
        return mapping
      elsif expansions.size > 0 && expansions.size == unparsed_values.size
        expansions.each_with_index do |expansion, index|
          unparsed_value = unparsed_values[index]
          if expansion =~ operator_expansion
            operator, argument, variables =
              parse_template_expansion(expansion)
            extract_method = "extract_#{operator}_operator"
            if ([extract_method, extract_method.to_sym] &
                private_methods).empty?
              raise InvalidTemplateOperatorError,
                "Invalid template operator: #{operator}"
            else
              begin
                send(
                  extract_method.to_sym, unparsed_value, processor,
                  argument, variables, mapping
                )
              rescue TemplateOperatorAbortedError
                return nil
              end
            end
          else
            name = expansion[variable_expansion, 1]
            value = unparsed_value
            if processor != nil && processor.respond_to?(:restore)
              value = processor.restore(name, value)
            end
            mapping[name] = value
          end
        end
        return mapping
      else
        return nil
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
    def parse_template_pattern(pattern, processor)
      reserved = Addressable::URI::CharacterClasses::RESERVED
      unreserved = Addressable::URI::CharacterClasses::UNRESERVED
      anything = reserved + unreserved
      operator_expansion =
        /\{-[a-zA-Z]+\|[#{anything}]+\|[#{anything}]+\}/
      variable_expansion = /\{([#{anything}]+?)(=([#{anything}]+))?\}/

      # Escape the pattern.  The two gsubs restore the escaped curly braces
      # back to their original form.  Basically, escape everything that isn't
      # within an expansion.
      escaped_pattern = Regexp.escape(
        pattern
      ).gsub(/\\\{(.*?)\\\}/) do |escaped|
        escaped.gsub(/\\(.)/, "\\1")
      end

      expansions = []

      # Create a regular expression that captures the values of the
      # variables in the URI.
      regexp_string = escaped_pattern.gsub(
        /#{operator_expansion}|#{variable_expansion}/
      ) do |expansion|
        expansions << expansion
        if expansion =~ operator_expansion
          capture_group = "(.*)"
          if processor != nil && processor.respond_to?(:match)
            # We can only lookup the match values for single variable
            # operator expansions.  Besides, ".*" is usually the only
            # reasonable value for multivariate operators anyways.
            operator, _, names, _ =
              parse_template_expansion(expansion)
            if ["prefix", "suffix", "list"].include?(operator)
              capture_group = "(#{processor.match(names.first)})"
            end
          end
          capture_group
        else
          capture_group = "(.*?)"
          if processor != nil && processor.respond_to?(:match)
            name = expansion[/\{([^\}=]+)(=[^\}]+)?\}/, 1]
            capture_group = "(#{processor.match(name)})"
          end
          capture_group
        end
      end

      # Ensure that the regular expression matches the whole URI.
      regexp_string = "^#{regexp_string}$"

      return expansions, Regexp.new(regexp_string)
    end
    private :parse_template_pattern

    ##
    # Parses a URI template expansion <tt>String</tt>.
    #
    # @param [String] expansion The operator <tt>String</tt>.
    #
    # @return [Array]
    #   A tuple of the operator, argument, variables.
    def parse_template_expansion(capture)
      operator, argument, variables = capture[1...-1].split("|")
      operator.gsub!(/^\-/, "")
      variables = variables.split(",").map { |var| var.gsub(/=.*$/, "") }
      return operator, argument, variables
    end
    private :parse_template_expansion


    ##
    # Extracts a URI Template opt operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_opt_operator(
        value, processor, argument, variables, mapping)
      if value != "" && value != argument
        raise TemplateOperatorAbortedError,
          "Value for template operator 'neg' was unexpected."
      end
    end
    private :extract_opt_operator

    ##
    # Extracts a URI Template neg operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_neg_operator(
        value, processor, argument, variables, mapping)
      if value != "" && value != argument
        raise TemplateOperatorAbortedError,
          "Value for template operator 'neg' was unexpected."
      end
    end
    private :extract_neg_operator

    ##
    # Extracts a URI Template prefix operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_prefix_operator(
        value, processor, argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'suffix' takes exactly one variable."
      end
      if value[0...argument.size] != argument
        raise TemplateOperatorAbortedError,
          "Value for template operator 'prefix' missing expected prefix."
      end
      values = value.split(argument)
      # Compensate for the crappy result from split.
      if value[-argument.size..-1] == argument
        values << ""
      end
      if values[0] == ""
        values.shift
      end
      if processor && processor.respond_to?(:restore)
        values.map! { |value| processor.restore(variables.first, value) }
      end
      mapping[variables.first] = values
    end
    private :extract_prefix_operator

    ##
    # Extracts a URI Template suffix operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_suffix_operator(
        value, processor, argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'suffix' takes exactly one variable."
      end
      if value[-argument.size..-1] != argument
        raise TemplateOperatorAbortedError,
          "Value for template operator 'suffix' missing expected suffix."
      end
      values = value.split(argument)
      # Compensate for the crappy result from split.
      if value[-argument.size..-1] == argument
        values << ""
      end
      if values[-1] == ""
        values.pop
      end
      if processor && processor.respond_to?(:restore)
        values.map! { |value| processor.restore(variables.first, value) }
      end
      mapping[variables.first] = values
    end
    private :extract_suffix_operator

    ##
    # Extracts a URI Template join operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_join_operator(value, processor, argument, variables, mapping)
      unparsed_values = value.split(argument)
      parsed_variables = []
      for unparsed_value in unparsed_values
        name = unparsed_value[/^(.+?)=(.+)$/, 1]
        parsed_variables << name
        parsed_value = unparsed_value[/^(.+?)=(.+)$/, 2]
        if processor && processor.respond_to?(:restore)
          parsed_value = processor.restore(name, parsed_value)
        end
        mapping[name] = parsed_value
      end
      if (parsed_variables & variables) != parsed_variables
        raise TemplateOperatorAbortedError,
          "Template operator 'join' variable mismatch: " +
          "#{parsed_variables.inspect}, #{variables.inspect}"
      end
    end
    private :extract_join_operator

    ##
    # Extracts a URI Template list operator.
    #
    # @param [String] value The unparsed value to extract from.
    # @param [#restore] processor The processor object.
    # @param [String] argument The argument to the operator.
    # @param [Array] variables The variables the operator is working on.
    # @param [Hash] mapping The mapping of variables to values.
    #
    # @return [String] The extracted result.
    def extract_list_operator(value, processor, argument, variables, mapping)
      if variables.size != 1
        raise InvalidTemplateOperatorError,
          "Template operator 'list' takes exactly one variable."
      end
      values = value.split(argument)
      if processor && processor.respond_to?(:restore)
        values.map! { |value| processor.restore(variables.first, value) }
      end
      mapping[variables.first] = values
    end
    private :extract_list_operator

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
        result.join!(uri)
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
        (sequence.unpack('C*').map { |c| "%" + ("%02x" % c).upcase }).join("")
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
          "Expected Class (String or Addressable::URI), " +
          "got #{returning.inspect}"
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
          "Expected Class (String or Addressable::URI), " +
          "got #{returning.inspect}"
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
          "Expected Class (String or Addressable::URI), " +
          "got #{returning.inspect}"
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
          Addressable::URI::CharacterClasses::UNRESERVED),
        :password => self.encode_component(components[:password],
          Addressable::URI::CharacterClasses::UNRESERVED),
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
      if options.has_key?(:authority)
        if (options.keys & [:userinfo, :user, :password, :host, :port]).any?
          raise ArgumentError,
            "Cannot specify both an authority and any of the components " +
            "within the authority."
        end
      end
      if options.has_key?(:userinfo)
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
            Addressable::URI.encode_component(
              Addressable::IDNA.unicode_normalize_kc(
                Addressable::URI.unencode_component(
                  self.scheme.strip.downcase)),
              Addressable::URI::CharacterClasses::SCHEME
            )
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
            Addressable::URI.encode_component(
              Addressable::IDNA.unicode_normalize_kc(
                Addressable::URI.unencode_component(self.user.strip)),
              Addressable::URI::CharacterClasses::UNRESERVED
            )
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

    ##
    # The password component for this URI.
    #
    # @return [String] The password component.
    def password
      return @password
    end

    ##
    # The password component for this URI, normalized.
    #
    # @return [String] The password component, normalized.
    def normalized_password
      @normalized_password ||= (begin
        if self.password
          if normalized_scheme =~ /https?/ && self.password.strip == "" &&
              (!self.user || self.user.strip == "")
            nil
          else
            Addressable::URI.encode_component(
              Addressable::IDNA.unicode_normalize_kc(
                Addressable::URI.unencode_component(self.password.strip)),
              Addressable::URI::CharacterClasses::UNRESERVED
            )
          end
        else
          nil
        end
      end)
    end

    ##
    # Sets the password component for this URI.
    #
    # @param [String, #to_str] new_password The new password component.
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

    ##
    # The userinfo component for this URI.
    # Combines the user and password components.
    #
    # @return [String] The userinfo component.
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

    ##
    # The userinfo component for this URI, normalized.
    #
    # @return [String] The userinfo component, normalized.
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

    ##
    # Sets the userinfo component for this URI.
    #
    # @param [String, #to_str] new_userinfo The new userinfo component.
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

    ##
    # The host component for this URI.
    #
    # @return [String] The host component.
    def host
      return @host
    end

    ##
    # The host component for this URI, normalized.
    #
    # @return [String] The host component, normalized.
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

    ##
    # Sets the host component for this URI.
    #
    # @param [String, #to_str] new_host The new host component.
    def host=(new_host)
      @host = new_host ? new_host.to_str : nil

      # Reset dependant values
      @authority = nil
      @normalized_host = nil

      # Ensure we haven't created an invalid URI
      validate()
    end

    ##
    # The authority component for this URI.
    # Combines the user, password, host, and port components.
    #
    # @return [String] The authority component.
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

    ##
    # The authority component for this URI, normalized.
    #
    # @return [String] The authority component, normalized.
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

    ##
    # Sets the authority component for this URI.
    #
    # @param [String, #to_str] new_authority The new authority component.
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

    ##
    # The port component for this URI.
    # This is the port number actually given in the URI.  This does not
    # infer port numbers from default values.
    #
    # @return [Integer] The port component.
    def port
      return @port
    end

    ##
    # The port component for this URI, normalized.
    #
    # @return [Integer] The port component, normalized.
    def normalized_port
      @normalized_port ||= (begin
        if self.class.port_mapping[normalized_scheme] == self.port
          nil
        else
          self.port
        end
      end)
    end

    ##
    # Sets the port component for this URI.
    #
    # @param [String, Integer, #to_s] new_port The new port component.
    def port=(new_port)
      if new_port != nil && new_port.respond_to?(:to_str)
        new_port = Addressable::URI.unencode_component(new_port.to_str)
      end
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

    ##
    # The inferred port component for this URI.
    # This method will normalize to the default port for the URI's scheme if
    # the port isn't explicitly specified in the URI.
    #
    # @return [Integer] The inferred port component.
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

    ##
    # The path component for this URI.
    #
    # @return [String] The path component.
    def path
      return (@path || "")
    end

    ##
    # The path component for this URI, normalized.
    #
    # @return [String] The path component, normalized.
    def normalized_path
      @normalized_path ||= (begin
        result = Addressable::URI.encode_component(
          Addressable::IDNA.unicode_normalize_kc(
            Addressable::URI.unencode_component(self.path.strip)),
          Addressable::URI::CharacterClasses::PATH
        )
        result = self.class.normalize_path(result)
        if result == "" &&
            ["http", "https", "ftp", "tftp"].include?(self.normalized_scheme)
          result = "/"
        end
        result
      end)
    end

    ##
    # Sets the path component for this URI.
    #
    # @param [String, #to_str] new_path The new path component.
    def path=(new_path)
      @path = (new_path || "").to_str
      if @path != "" && @path[0..0] != "/" && host != nil
        @path = "/#{@path}"
      end

      # Reset dependant values
      @normalized_path = nil
    end

    ##
    # The basename, if any, of the file in the path component.
    #
    # @return [String] The path's basename.
    def basename
      # Path cannot be nil
      return File.basename(self.path).gsub(/;[^\/]*$/, "")
    end

    ##
    # The extname, if any, of the file in the path component.
    # Empty string if there is no extension.
    #
    # @return [String] The path's extname.
    def extname
      return nil unless self.path
      return File.extname(self.basename)
    end

    ##
    # The query component for this URI.
    #
    # @return [String] The query component.
    def query
      return @query
    end

    ##
    # The query component for this URI, normalized.
    #
    # @return [String] The query component, normalized.
    def normalized_query
      @normalized_query ||= (begin
        if self.query
          Addressable::URI.encode_component(
            Addressable::IDNA.unicode_normalize_kc(
              Addressable::URI.unencode_component(self.query.strip)),
            Addressable::URI::CharacterClasses::QUERY
          )
        else
          nil
        end
      end)
    end

    ##
    # Sets the query component for this URI.
    #
    # @param [String, #to_str] new_query The new query component.
    def query=(new_query)
      @query = new_query ? new_query.to_str : nil

      # Reset dependant values
      @normalized_query = nil
    end

    ##
    # Converts the query component to a Hash value.
    #
    # @option [Symbol] notation
    #   May be one of <tt>:flat</tt>, <tt>:dot</tt>, or <tt>:subscript</tt>.
    #   The <tt>:dot</tt> notation is not supported for assignment.
    #   Default value is <tt>:subscript</tt>.
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

    ##
    # Sets the query component for this URI from a Hash object.
    #
    # @param [Hash, #to_hash] new_query_values The new query values.
    def query_values=(new_query_values)
      @query = (new_query_values.to_hash.inject([]) do |accumulator, pair|
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

    ##
    # The fragment component for this URI.
    #
    # @return [String] The fragment component.
    def fragment
      return @fragment
    end

    ##
    # The fragment component for this URI, normalized.
    #
    # @return [String] The fragment component, normalized.
    def normalized_fragment
      @normalized_fragment ||= (begin
        if self.fragment
          Addressable::URI.encode_component(
            Addressable::IDNA.unicode_normalize_kc(
              Addressable::URI.unencode_component(self.fragment.strip)),
            Addressable::URI::CharacterClasses::FRAGMENT
          )
        else
          nil
        end
      end)
    end

    ##
    # Sets the fragment component for this URI.
    #
    # @param [String, #to_str] new_fragment The new fragment component.
    def fragment=(new_fragment)
      @fragment = new_fragment ? new_fragment.to_str : nil

      # Reset dependant values
      @normalized_fragment = nil
    end

    ##
    # Determines if the scheme indicates an IP-based protocol.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the scheme indicates an IP-based protocol.
    #   <tt>false</tt> otherwise.
    def ip_based?
      if self.scheme
        return self.class.ip_based_schemes.include?(
          self.scheme.strip.downcase)
      end
      return false
    end

    ##
    # Determines if the URI is relative.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the URI is relative.
    #   <tt>false</tt> otherwise.
    def relative?
      return self.scheme.nil?
    end

    ##
    # Determines if the URI is absolute.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the URI is absolute.
    #   <tt>false</tt> otherwise.
    def absolute?
      return !relative?
    end

    ##
    # Joins two URIs together.
    #
    # @param [String, Addressable::URI, #to_str] The URI to join with.
    #
    # @return [Addressable::URI] The joined URI.
    def join(uri)
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
    alias_method :+, :join

    ##
    # Destructive form of <tt>join</tt>.
    #
    # @param [String, Addressable::URI, #to_str] The URI to join with.
    #
    # @return [Addressable::URI] The joined URI.
    #
    # @see Addressable::URI#join
    def join!(uri)
      replace_self(self.join(uri))
    end

    ##
    # Merges a URI with a <tt>Hash</tt> of components.
    # This method has different behavior from <tt>join</tt>.  Any components
    # present in the <tt>hash</tt> parameter will override the original
    # components.  The path component is not treated specially.
    #
    # @param [Hash, Addressable::URI, #to_hash] The components to merge with.
    #
    # @return [Addressable::URI] The merged URI.
    #
    # @see Hash#merge
    def merge(hash)
      if !hash.respond_to?(:to_hash)
        raise TypeError, "Can't convert #{hash.class} into Hash."
      end
      hash = hash.to_hash

      if hash.has_key?(:authority)
        if (hash.keys & [:userinfo, :user, :password, :host, :port]).any?
          raise ArgumentError,
            "Cannot specify both an authority and any of the components " +
            "within the authority."
        end
      end
      if hash.has_key?(:userinfo)
        if (hash.keys & [:user, :password]).any?
          raise ArgumentError,
            "Cannot specify both a userinfo and either the user or password."
        end
      end

      uri = Addressable::URI.new
      uri.validation_deferred = true
      uri.scheme =
        hash.has_key?(:scheme) ? hash[:scheme] : self.scheme
      if hash.has_key?(:authority)
        uri.authority =
          hash.has_key?(:authority) ? hash[:authority] : self.authority
      end
      if hash.has_key?(:userinfo)
        uri.userinfo =
          hash.has_key?(:userinfo) ? hash[:userinfo] : self.userinfo
      end
      if !hash.has_key?(:userinfo) && !hash.has_key?(:authority)
        uri.user =
          hash.has_key?(:user) ? hash[:user] : self.user
        uri.password =
          hash.has_key?(:password) ? hash[:password] : self.password
      end
      if !hash.has_key?(:authority)
        uri.host =
          hash.has_key?(:host) ? hash[:host] : self.host
        uri.port =
          hash.has_key?(:port) ? hash[:port] : self.port
      end
      uri.path =
        hash.has_key?(:path) ? hash[:path] : self.path
      uri.query =
        hash.has_key?(:query) ? hash[:query] : self.query
      uri.fragment =
        hash.has_key?(:fragment) ? hash[:fragment] : self.fragment
      uri.validation_deferred = false

      return uri
    end

    ##
    # Destructive form of <tt>merge</tt>.
    #
    # @param [Hash, Addressable::URI, #to_hash] The components to merge with.
    #
    # @return [Addressable::URI] The merged URI.
    #
    # @see Addressable::URI#merge
    def merge!(uri)
      replace_self(self.merge(uri))
    end

    ##
    # Returns the shortest normalized relative form of this URI that uses the
    # supplied URI as a base for resolution.  Returns an absolute URI if
    # necessary.  This is effectively the opposite of <tt>route_to</tt>.
    #
    # @param [String, Addressable::URI, #to_str] uri The URI to route from.
    #
    # @return [Addressable::URI]
    #   The normalized relative URI that is equivalent to the original URI.
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

    ##
    # Returns the shortest normalized relative form of the supplied URI that
    # uses this URI as a base for resolution.  Returns an absolute URI if
    # necessary.  This is effectively the opposite of <tt>route_from</tt>.
    #
    # @param [String, Addressable::URI, #to_str] uri The URI to route to.
    #
    # @return [Addressable::URI]
    #   The normalized relative URI that is equivalent to the supplied URI.
    def route_to(uri)
      return self.class.parse(uri).route_from(self)
    end

    ##
    # Returns a normalized URI object.
    #
    # NOTE: This method does not attempt to fully conform to specifications.
    # It exists largely to correct other people's failures to read the
    # specifications, and also to deal with caching issues since several
    # different URIs may represent the same resource and should not be
    # cached multiple times.
    #
    # @return [Addressable::URI] The normalized URI.
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

      return Addressable::URI.new(
        :scheme => normalized_scheme,
        :authority => normalized_authority,
        :path => normalized_path,
        :query => normalized_query,
        :fragment => normalized_fragment
      )
    end

    ##
    # Destructively normalizes this URI object.
    #
    # @return [Addressable::URI] The normalized URI.
    #
    # @see Addressable::URI#normalize
    def normalize!
      replace_self(self.normalize)
    end

    ##
    # Creates a URI suitable for display to users.  If semantic attacks are
    # likely, the application should try to detect these and warn the user.
    # See <a href="http://www.ietf.org/rfc/rfc3986.txt">RFC 3986</a>,
    # section 7.6 for more information.
    #
    # @return [Addressable::URI] A URI suitable for display purposes.
    def display_uri
      display_uri = self.normalize
      display_uri.instance_variable_set("@host",
        ::Addressable::IDNA.to_unicode(display_uri.host))
      return display_uri
    end

    ##
    # Returns <tt>true</tt> if the URI objects are equal.  This method
    # normalizes both URIs before doing the comparison, and allows comparison
    # against <tt>Strings</tt>.
    #
    # @param [Object] uri The URI to compare.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the URIs are equivalent, <tt>false</tt> otherwise.
    def ===(uri)
      if uri.respond_to?(:normalize)
        uri_string = uri.normalize.to_s
      else
        begin
          uri_string = ::Addressable::URI.parse(uri).normalize.to_s
        rescue InvalidURIError, TypeError
          return false
        end
      end
      return self.normalize.to_s == uri_string
    end

    ##
    # Returns <tt>true</tt> if the URI objects are equal.  This method
    # normalizes both URIs before doing the comparison.
    #
    # @param [Object] uri The URI to compare.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the URIs are equivalent, <tt>false</tt> otherwise.
    def ==(uri)
      return false unless uri.kind_of?(self.class)
      return self.normalize.to_s == uri.normalize.to_s
    end

    ##
    # Returns <tt>true</tt> if the URI objects are equal.  This method
    # does NOT normalize either URI before doing the comparison.
    #
    # @param [Object] uri The URI to compare.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if the URIs are equivalent, <tt>false</tt> otherwise.
    def eql?(uri)
      return false unless uri.kind_of?(self.class)
      return self.to_s == uri.to_s
    end

    ##
    # A hash value that will make a URI equivalent to its normalized
    # form.
    #
    # @return [Integer] A hash of the URI.
    def hash
      return (self.normalize.to_s.hash * -1)
    end

    ##
    # Clones the URI object.
    #
    # @return [Addressable::URI] The cloned URI.
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
    # @param [Symbol] *components The components to be omitted.
    #
    # @return [Addressable::URI] The URI with components omitted.
    #
    # @see Addressable::URI#omit
    def omit!(*components)
      replace_self(self.omit(*components))
    end

    ##
    # Converts the URI to a <tt>String</tt>.
    #
    # @return [String] The URI's <tt>String</tt> representation.
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

    ##
    # URI's are glorified <tt>Strings</tt>.  Allow implicit conversion.
    alias_method :to_str, :to_s

    ##
    # Returns a Hash of the URI components.
    #
    # @return [Hash] The URI as a <tt>Hash</tt> of components.
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

    ##
    # Returns a <tt>String</tt> representation of the URI object's state.
    #
    # @return [String] The URI object's state, as a <tt>String</tt>.
    def inspect
      sprintf("#<%s:%#0x URI:%s>", self.class.to_s, self.object_id, self.to_s)
    end

    ##
    # If URI validation needs to be disabled, this can be set to true.
    #
    # @return [TrueClass, FalseClass]
    #   <tt>true</tt> if validation has been deferred,
    #   <tt>false</tt> otherwise.
    def validation_deferred
      @validation_deferred ||= false
    end

    ##
    # If URI validation needs to be disabled, this can be set to true.
    #
    # @param [TrueClass, FalseClass] new_validation_deferred
    #   <tt>true</tt> if validation will be deferred,
    #   <tt>false</tt> otherwise.
    def validation_deferred=(new_validation_deferred)
      @validation_deferred = new_validation_deferred
      validate unless @validation_deferred
    end

  private
    ##
    # Resolves paths to their simplest form.
    #
    # @param [String] path The path to normalize.
    #
    # @return [String] The normalized path.
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

    ##
    # Replaces the internal state of self with the specified URI's state.
    # Used in destructive operations to avoid massive code repetition.
    #
    # @param [Addressable::URI] uri The URI to replace <tt>self</tt> with.
    #
    # @return [Addressable::URI] <tt>self</tt>.
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
