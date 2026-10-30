# frozen_string_literal: true

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


require "spec_helper"

require "timeout"
require "addressable/template"

module TemplateMatchSpec
  OPERATORS = [nil, "+", "#", "/", ".", ";", "?", "&"]

  # Addressable 2.9.0's Template#parse_new_template_pattern, kept verbatim as
  # a compatibility oracle. The constants it uses have not changed.
  LEGACY_PARSE_NEW_TEMPLATE_PATTERN = <<-'RUBY'
    def parse_new_template_pattern(pattern, processor = nil)
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
        leader = Regexp.escape(LEADERS.fetch(operator, ''))
        joiner = Regexp.escape(JOINERS.fetch(operator, ','))
        varspecs = varlist.split(',')
        combined = varspecs.map do |varspec|
          _, name, modifier = *varspec.match(VARSPEC)

          result = processor && processor.respond_to?(:match) ? processor.match(name) : nil
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
              "#{ UNRESERVED.gsub('\.', '') }*?"
            when ';'
              "#{ UNRESERVED }*=?#{ UNRESERVED }*?"
            when '?'
              "#{ UNRESERVED }*=#{ UNRESERVED }*?"
            when '&'
              "#{ UNRESERVED }*=#{ UNRESERVED }*?"
            else
              "#{ UNRESERVED }*?"
            end
            if modifier == '*'
              seg = case operator
                    when '+', '#' then "#{RESERVED_NO_COMMA}*+"
                    else group
                    end
              joiner_pattern = operator.nil? ? joiner : "#{joiner}?"
              "(?<#{name}>#{seg}(?:#{joiner_pattern}#{seg})*)?"
            elsif varspecs.size > 1 && (operator == '+' || operator == '#') &&
                  varspec != varspecs.last
              "(?<#{name}>#{RESERVED_NO_COMMA}*+)?"
            else
              "(?<#{name}>#{group})?"
            end
          end
        end.join("#{joiner}?")
        "(?:|#{leader}#{combined})"
      end

      # Ensure that the regular expression matches the whole URI.
      regexp_string = "\\A#{regexp_string}\\z"
      return expansions, Regexp.new(regexp_string)
    end
  RUBY

  module Legacy
    %w[
      EXPRESSION VARSPEC LEADERS JOINERS RESERVED RESERVED_NO_COMMA UNRESERVED
    ].each do |name|
      const_set(name, Addressable::Template.const_get(name))
    end

    module_eval(LEGACY_PARSE_NEW_TEMPLATE_PATTERN)
    extend self
  end

  def self.legacy_regexp(pattern)
    Legacy.parse_new_template_pattern(pattern)[1]
  end

  def self.regexp(pattern)
    Addressable::Template.new(pattern).send(:parse_template_pattern, pattern)[1]
  end

  # The expression without the \A and \z anchors around the whole template.
  def self.unanchored(regexp)
    regexp.source[/\A\\A(.*)\\z\z/m, 1]
  end

  def self.leader(operator)
    Addressable::Template::LEADERS.fetch(operator, "")
  end

  def self.joiner(operator)
    Addressable::Template::JOINERS.fetch(operator, ",")
  end

  # Every position at which the expression can stop matching a prefix of the
  # string, in the order that the regular expression engine tries them. Two
  # expressions that give the same order behave the same way wherever they
  # appear in a template.
  def self.end_positions(expression, string)
    remaining = (0..string.size).to_a
    order = []
    until remaining.empty?
      stops = remaining.map { |index| "(?=.{#{string.size - index}}\\z)" }
      match = Regexp.new(
        "\\A#{expression}(?:#{stops.join("|")})", Regexp::MULTILINE
      ).match(string)
      break unless match
      order << match[0].size
      remaining.delete(match[0].size)
    end
    order
  end

  # The named captures of a match, or nil. MatchData#named_captures needs
  # Ruby 2.4. With duplicate names, match[name] gives the last group with
  # that name that matched, as named_captures does.
  def self.named_captures(match)
    match && Hash[match.names.map { |name| [name, match[name]] }]
  end

  # Every string of up to max_length tokens drawn from alphabet.
  def self.strings(alphabet, max_length)
    (0..max_length).flat_map do |length|
      alphabet.repeated_permutation(length).map(&:join)
    end.uniq
  end

  def self.alphabet(operator, *extra)
    ([leader(operator), joiner(operator), "a", "=", "%41"] + extra).
      reject(&:empty?).uniq
  end
end

describe Addressable::Template, "#match" do
  context "compared with 2.9.0" do
    {
      ["{;b*}", ";b==a"] => {"b" => {"b" => ""}},
      ["{;a*}", ";a=b=c;d"] => {"a" => {"a" => "b", "d" => ""}},
      ["{;a*}", ";a;;b"] => {"a" => {"a" => "", nil => "", "b" => ""}},
      ["{&b*}", "&k=ab%3Bb="] => {"b" => {"k" => "ab;b"}},
      ["{?a*}", "?a=b=c&d=e"] => {"a" => {"a" => "b", "d" => "e"}},
      ["{?a*}", "?a=bc=d"] => {"a" => {"a" => "bc"}},
      ["{;b*,c*}", ";n=ak=ab;c=a2Cb"] => {
        "b" => {"n" => "ak", "c" => "a2Cb"}, "c" => {}
      },
      ["{?a*,a*,a*}", "?a=aba=ab&a=ab"] => {"a" => {"a" => "ab"}},
      ["{?a*,c*}", "?a=b=c&d=e"] => {
        "a" => {"a" => "b", "d" => "e"}, "c" => nil
      },
      ["{&a*}{&b}", "&x=1=2&b=3"] => {
        "a" => {"x" => "1", "b" => "3"}, "b" => nil
      },
      ["{;a*}{?b*}", ";a=1;b?c=d=e"] => {
        "a" => {"a" => "1", "b" => ""}, "b" => {"c" => "d"}
      },
      ["{/a*}{/b}", "/x/y/z"] => {"a" => ["x", "y", "z"], "b" => nil},
      ["{.a*}{.b}", ".x.y.z"] => {"a" => ["x", "y", "z"], "b" => nil},
      ["{a*}{b}", "x,y,z"] => {"a" => ["x,y,"], "b" => "z"},
      # With several variables, a value without a joiner goes to the last
      # variable for /, . and the default operator...
      ["{/a,b,c}", "/x"] => {"a" => "", "b" => "", "c" => "x"},
      ["{/a,b,c}", "/x/y"] => {"a" => "", "b" => "x", "c" => "y"},
      ["{.a,b}.json", ".x.json"] => {"a" => "", "b" => "x"},
      ["{a,b,c}", "x,y"] => {"a" => "", "b" => "x", "c" => "y"},
      ["{/a,b*}", "/x/y"] => {"a" => "", "b" => ["x", "y"]},
      # ...and to the first variable for ;.
      ["{;a,b}", ";a=1"] => {"a" => "", "b" => nil, "1" => ""},
      ["{;a,b}", ";a=1;b=2"] => {"a" => "1", "b" => "2"},
      ["{;a,b*}x", ";ax"] => {"a" => "", "b" => {}},
      # An expression directly followed by one that can match anything it
      # could is empty.
      ["{+a}{+b}{+c}", "xyz"] => {"a" => nil, "b" => nil, "c" => "xyz"},
      ["{+a}{+b}{+c}", "x,y/z"] => {"a" => nil, "b" => nil, "c" => "x,y/z"},
      ["{+a}{+b}x", "pqx"] => {"a" => nil, "b" => "pq"},
      ["{a}{b}{c}", "xyz"] => {"a" => nil, "b" => nil, "c" => "xyz"},
      ["{.a,b}{c}", ".x.yz"] => {"a" => nil, "b" => nil, "c" => ".x.yz"},
      ["{/a}{+b}", "/x/y"] => {"a" => nil, "b" => "/x/y"},
      ["{a}{+b}{c}{+d}", "w/x"] => {
        "a" => nil, "b" => nil, "c" => nil, "d" => "w/x"
      },
      ["{+a,b}{+c,d}", "x,y,z"] => {
        "a" => nil, "b" => nil, "c" => "x", "d" => "y,z"
      },
      ["{#a,b}{+c,d}", "#x,y"] => {
        "a" => nil, "b" => nil, "c" => "#x", "d" => "y"
      },
      ["{a,b}{c*}", "x,y,z"] => {"a" => nil, "b" => nil, "c" => ["x,y,z"]},
      ["{.a}{c*}", ".x,y"] => {"a" => nil, "c" => [".x,y"]},
      ["{a*}{c,d*}", "x,y"] => {"a" => nil, "c" => "", "d" => ["x,y"]},
      # An exploded {+b*} only ends where a run of characters ends.
      ["{+a}{+b*}x", "p,qx"] => {"a" => "p,q", "b" => nil},
      # {b} can't match "/", so {+a} isn't always empty.
      ["{+a}{b}", "p/q"] => {"a" => "p/", "b" => "q"},
      ["{+a}{b}", "p/qr"] => {"a" => "p/", "b" => "qr"},
      ["{#a}{b}", "#p/q"] => {"a" => "p/", "b" => "q"},
      # In + and # expressions, the earlier variables take one value each.
      ["{+v1,v2,v3}", "a"] => {"v1" => "a", "v2" => "", "v3" => ""},
      ["{+v1,v2,v3}", "a,b"] => {"v1" => "a", "v2" => "b", "v3" => ""},
      ["{+v1,v2,v3}", "a,b,c,d"] => {
        "v1" => "a", "v2" => "b", "v3" => "c,d"
      },
      ["{+v1,v2,v3}x", "a,bx"] => {"v1" => "a", "v2" => nil, "v3" => "b"},
      ["{+v1,v2,v3}x", "a,b,x"] => {"v1" => "a", "v2" => "b", "v3" => ""},
      ["{#v1,v2}", "#,b"] => {"v1" => "", "v2" => "b"},
      ["{+v1,v2},x", "a,b,x"] => {"v1" => "a", "v2" => "b"},
      ["{+v1,v2,v1}", "a,b,c"] => {"v1" => "", "v2" => "a"}
    }.each do |(pattern, uri), mapping|
      it "matches #{uri.inspect} against #{pattern} as 2.9.0 did" do
        expect(Addressable::Template.new(pattern).match(uri).mapping).to eq(
          mapping
        )
      end
    end

    TemplateMatchSpec::OPERATORS.product(["", "*"]).each do |operator, modifier|
      pattern = "{#{operator}a#{modifier}}"
      it "tries the same end positions in the same order for #{pattern}" do
        legacy = TemplateMatchSpec.unanchored(
          TemplateMatchSpec.legacy_regexp(pattern)
        )
        current = TemplateMatchSpec.unanchored(
          TemplateMatchSpec.regexp(pattern)
        )
        alphabet = TemplateMatchSpec.alphabet(operator)
        TemplateMatchSpec.strings(alphabet, 5).each do |string|
          expect(TemplateMatchSpec.end_positions(current, string)).to eq(
            TemplateMatchSpec.end_positions(legacy, string)
          ), "for #{string.inspect}"
        end
      end
    end

    TemplateMatchSpec::OPERATORS.each do |operator|
      [
        "{#{operator}a,b,c}", "{#{operator}a,b*}", "{#{operator}a*,b}",
        "{#{operator}a,b}x", "{#{operator}a,b}{#{operator}c}",
        "{#{operator}a}{+b}", "{#{operator}a,b*}{+c}", "{#{operator}a}{b}",
        "{#{operator}a*}{b}{+c}", "{#{operator}a}{+b}x",
        "{#{operator}a,b,c}x", "{#{operator}a,b},x", "{#{operator}a,b,a}",
        "{#{operator}a,b:2,c}/", "{#{operator}a,b}{+c,d}",
        "{#{operator}a}{c*}", "{#{operator}a,b}{c,d*}", "{#{operator}a}{+c*}x",
        "{#{operator}a,b}{c,d}"
      ].each do |pattern|
        it "captures the same values as 2.9.0 for #{pattern}" do
          legacy = TemplateMatchSpec.legacy_regexp(pattern)
          current = TemplateMatchSpec.regexp(pattern)
          alphabet = TemplateMatchSpec.alphabet(operator, "x")
          TemplateMatchSpec.strings(alphabet, 5).each do |string|
            expected = legacy.match(string)
            actual = current.match(string)
            expect(TemplateMatchSpec.named_captures(actual)).to eq(
              TemplateMatchSpec.named_captures(expected)
            ), "for #{string.inspect}"
          end
        end
      end
    end

    it "calls a processor's match method once per variable, in order" do
      processor = Object.new
      names = []
      processor.define_singleton_method(:match) do |name|
        names << name
        nil
      end
      Addressable::Template.new("{/a,b}{;c}").match("/x/y;c=1", processor)
      expect(names).to eq(["a", "b", "c"])
    end

    it "keeps 2.9.0's matching of adjacent expressions with a processor" do
      processor = Object.new
      def processor.match(name)
        nil
      end
      template = Addressable::Template.new("{+a}{+b}")
      expect(template.match("xy", processor).mapping).to eq(
        "a" => nil, "b" => "xy"
      )
    end

    it "keeps 2.9.0's matching when a processor supplies a pattern" do
      processor = Object.new
      def processor.match(name)
        name == "b" ? "[0-9]+" : nil
      end
      template = Addressable::Template.new("{/a,b,c}")
      expect(template.match("/x/1/y", processor).mapping).to eq(
        "a" => "x", "b" => "1", "c" => "y"
      )
      expect(template.match("/x1", processor).mapping).to eq(
        "a" => "x", "b" => "1", "c" => ""
      )
    end
  end

  context "with adversarial input" do
    {
      "{/foo*}" => "/" + ("%41/" * 1000) + "!",
      "{/foo*}{?q*}" => "/" + ("a/" * 500) + "?" + ("a=" * 500) + "!",
      "{/foo*,bar}" => "/" + ("a/" * 1000) + "!",
      "{/foo*}.json" => "/" + ("a/" * 1000) + ".jso",
      "{/foo*} (empty members)" => ("/" * 2000) + "!",
      "{.foo*} (empty members)" => ("." * 2000) + "!",
      "x{.foo*}{;bar*}" => "x." + ("a." * 500) + ";" + ("a=" * 500) + "!",
      "{foo*} (empty members)" => ("," * 2000) + "!",
      "{;foo*}" => ";" + ("a=" * 1000) + "!",
      "{;foo*} (percent-encoded)" => ";" + ("%41=" * 1000) + "!",
      "{;foo*} (empty members)" => (";" * 2000) + "!",
      "{;foo*} (equals signs)" => ";" + ("=" * 2000) + "!",
      "{;foo*,bar}" => ";" + ("a=" * 1000) + "!",
      "{?foo*}" => "?" + ("a=" * 1000) + "!",
      "{?foo*} (percent-encoded)" => "?" + ("%41=" * 1000) + "!",
      "{?foo*} (equals signs)" => "?" + ("=" * 2000) + "!",
      "{?foo*,bar}" => "?" + ("a=" * 1000) + "!",
      "{&foo*}" => "&" + ("a=" * 1000) + "!",
      "{/foo,bar,baz}" => "/" + ("a" * 2000) + "!",
      "{/a,b,c,d,e}" => "/" + ("a" * 1000) + "!",
      "{/foo,bar}{/baz,qux}" => "/" + ("a" * 2000) + "!",
      "http://example.com/repos{/owner,repo,ref}" =>
        "http://example.com/repos/" + ("a" * 2048) + "!",
      "{.foo,bar,baz}" => "." + ("a" * 2000) + "!",
      "{foo,bar,baz}" => ("a" * 2000) + "!",
      "{foo,bar,baz} (percent-encoded)" => ("%41" * 1000) + "!",
      "{;foo}" => ";" + ("a" * 8000) + "!",
      "{;foo,bar,baz}" => ";" + ("a" * 8000) + "!",
      "{;foo,bar,baz} (values)" => ";" + ("a=" * 1000) + "!",
      "{;foo,bar*,baz}" => ";" + ("a" * 4000) + "!",
      "{?foo,bar,baz}" => "?" + ("a=" * 1000) + "!",
      "{&foo,bar,baz}" => "&" + ("a=" * 1000) + "!",
      "{+a}{+b}{+c}" => ("a" * 4000) + " ",
      "{a}{b}{c}" => ("a" * 4000) + "!",
      "{.a,b}{c}" => "." + ("a" * 4000) + "!",
      "{/a}{+b}" => "/" + ("a" * 4000) + " ",
      "{a}{+b}{c}{+d}" => ("a" * 4000) + " ",
      "{+a}{b}" => ("a/" * 4000) + " ",
      "{#a}{b}" => "#" + ("a/" * 4000) + " ",
      "{+v1,v2,v3,v4,v5,v6,v7,v8,v9,v10}" => ("a," * 4000) + " ",
      "{+v1,v2,v3,v4,v5,v6,v7,v8,v9,v10}x" => ("a," * 4000) + " ",
      "{#v1,v2,v3,v4,v5,v6,v7,v8}" => "#" + ("," * 8000) + " ",
      "{+v1,v2,v3,v4,v5,v6,v7,v8}{+c,d}" => ("a," * 2000) + " ",
      "{a,b}{c*}" => ("a," * 2000) + "!",
      "{.a,b}{c,d*}" => "." + ("a" * 4000) + "!"
    }.each do |name, payload|
      it "rejects a long payload for #{name} in linear time" do
        template = Addressable::Template.new(name.split(" ").first)
        expect do
          Timeout.timeout(10) do
            expect(template.match(payload)).to be_nil
          end
        end.not_to raise_error
      end
    end
  end
end
