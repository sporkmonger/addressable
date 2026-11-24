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

  # A direct version of Template#parse_new_template_pattern, without the
  # changes that keep matching from backtracking catastrophically. It's the
  # reference for the order in which a match tries its choices. The pairs
  # of the ;, ? and & variables that aren't exploded are one run, in any
  # order, of the names of those variables, in the first one's place.
  REFERENCE_PARSE_NEW_TEMPLATE_PATTERN = <<-'RUBY'
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
        named = varspecs.reject { |varspec| varspec[VARSPEC, 2] == '*' }
        first_named = varspecs.index { |varspec| varspec[VARSPEC, 2] != '*' }
        names = named.map { |varspec| varspec[VARSPEC, 1] }.uniq
        names = names.sort_by { |name| -name.size }
        names = "(?:#{names.map { |name| Regexp.escape(name) }.join('|')})"
        pair = if operator == ';'
          "#{names}(?:=#{UNRESERVED}*?)?"
        else
          "#{names}=#{UNRESERVED}*?"
        end
        combined = varspecs.each_with_index.map do |varspec, position|
          _, name, modifier = *varspec.match(VARSPEC)
          if [';', '?', '&'].include?(operator) && modifier != '*'
            next position == first_named ?
              "(?<#{name}>#{pair}(?:#{joiner}#{pair})*)?" : "(?<#{name}>)"
          end
          # In ; expansion, a later variable starts where a pair starts, not
          # in the middle of the name or value before it.
          start = operator == ';' && position > 0 ?
            "(?<![#{Addressable::URI::CharacterClasses::UNRESERVED}])" \
            "(?<![^\\x00-\\x7F])" : ""

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
              if start.empty?
                "(?<#{name}>#{seg}(?:#{joiner_pattern}#{seg})*)?"
              else
                "(?<#{name}>(?:#{start}#{seg}(?:#{joiner_pattern}#{seg})*)?)"
              end
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

  module Reference
    %w[
      EXPRESSION VARSPEC LEADERS JOINERS RESERVED RESERVED_NO_COMMA UNRESERVED
    ].each do |name|
      const_set(name, Addressable::Template.const_get(name))
    end

    module_eval(REFERENCE_PARSE_NEW_TEMPLATE_PATTERN)
    extend self
  end

  # The reference's expressions, put together with the template's literal
  # text and nothing else: every choice stays open, so a template that
  # commits to a choice is compared with one that can change it.
  def self.reference_regexp(pattern)
    template = Addressable::Template.new(pattern)
    _, expressions, literals, literal_sources =
      template.send(:template_parts, pattern)
    sources = expressions.map do |expression|
      Reference.parse_new_template_pattern(expression)[1].source[
        /\A\\A(.*)\\z\z/m, 1
      ]
    end
    Regexp.new(template.send(
      :assemble_regexp, expressions, literals, literal_sources, sources, [],
      false
    ))
  end

  # The regexp that commits to choices, which engines that can't match the
  # one that keeps every choice open in linear time use.
  def self.regexp(pattern)
    committed(Addressable::Template.new(pattern)).send(
      :parse_template_pattern, pattern
    )[1]
  end

  # The template, using the regexp that commits to choices on every Ruby.
  def self.committed(template)
    template.define_singleton_method(:linear_time?) { |_| false }
    template
  end

  # A template with one block, without the \A and \z anchors and any atomic
  # group around it.
  def self.unanchored(regexp)
    source = regexp.source
    source[/\A\A\(\?>(.*)\z\)\z/m, 1] || source[/\A\A(.*)\z\z/m, 1]
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

  # Whether the template keeps a choice that the reference could change for
  # this string. An expression's variables don't divide the same text in
  # more than one way, so that a URI that doesn't match is rejected in
  # linear time:
  #
  # * An exploded /, . or default variable before unexploded ones takes
  #   whole members, so its empty members differ.
  # * A ? or & variable after an exploded one starts after an empty member,
  #   so a value after an empty first member differs.
  # * The variables of a + or # expression take one value each, in order,
  #   with a name that's repeated.
  def self.committed?(pattern, operator, string)
    leader = leader(operator)
    joiner = joiner(operator)
    shape = pattern.sub(operator.to_s, "")
    case operator
    when nil, "/", "."
      ["{a*,b}", "{a*,b}x", "{a*,b,c}x"].include?(shape) &&
        (string.start_with?(leader + joiner) || string.include?(joiner * 2))
    when "?", "&"
      ["{a*,b,c*}", "{a*,c*,b,b}", "{a*,b,c}x"].include?(shape) &&
        string.start_with?(leader + joiner)
    when "+", "#"
      shape == "{a,b,a}"
    else
      false
    end
  end
end

describe Addressable::Template, "#match" do
  context "when a URI can be split between variables more than one way" do
    {
      ["{;a*}", ";a;;b"] => {"a" => {"a" => "", nil => "", "b" => ""}},
      ["{/a*}{/b}", "/x/y/z"] => {"a" => ["x", "y", "z"], "b" => nil},
      ["{.a*}{.b}", ".x.y.z"] => {"a" => ["x", "y", "z"], "b" => nil},
      # A member can be empty, but a joiner before a later variable in the
      # same expression isn't one.
      ["{a*}{b}", "x,y,z"] => {"a" => ["x", "y", ""], "b" => "z"},
      ["{a*,b}", "x,y,z"] => {"a" => ["x", "y", "z"], "b" => nil},
      ["{a*}", "x,,y,"] => {"a" => ["x", "", "y", ""]},
      ["{/a*}", "/x/"] => {"a" => ["x", ""]},
      ["{/segments*}", "/a/b/"] => {"segments" => ["a", "b", ""]},
      ["{/segments*}", "/"] => {"segments" => [""]},
      ["{/segments*}", ""] => {"segments" => nil},
      ["{+d*,a}?", ";,,x?"] => {"d" => [";", "", "x"], "a" => nil},
      ["{\#a*,d*,b}=", "\#,,="] => {"a" => ["", "", ""], "d" => nil, "b" => nil},
      # In an expression with several variables, each takes as much as it
      # can, from the first: an exploded variable every member left, and
      # another variable one member. A variable with nothing left is
      # undefined. This is the same for /, ., the default operator, + and #.
      ["{a*,b,c}", "x,y,z"] => {"a" => ["x", "y", "z"], "b" => nil, "c" => nil},
      ["{/a,b,c}", "/x"] => {"a" => "x", "b" => nil, "c" => nil},
      ["{/a,b,c}", "/x/y"] => {"a" => "x", "b" => "y", "c" => nil},
      ["{/a,b}", "/x/"] => {"a" => "x", "b" => ""},
      ["{.a,b}.json", ".x.json"] => {"a" => "x", "b" => nil},
      ["{a,b,c}", "x,y"] => {"a" => "x", "b" => "y", "c" => nil},
      ["{/a,b*}", "/x/y"] => {"a" => "x", "b" => ["y"]},
      ["{/a,b*}", "/x/y/z"] => {"a" => "x", "b" => ["y", "z"]},
      ["{/a*,b}", "/x/y"] => {"a" => ["x", "y"], "b" => nil},
      ["{.a,b*}", ".x.y.z"] => {"a" => "x", "b" => ["y", "z"]},
      # A ;, ? or & variable that isn't exploded takes the pair with its
      # own name.
      ["{;a,b}", ";a=1"] => {"a" => "1", "b" => nil},
      ["{;a,b}", ";a=1;b=2"] => {"a" => "1", "b" => "2"},
      ["{;a,b*}x", ";ax"] => {"a" => "", "b" => {}},
      # With several exploded variables, the first one takes the values...
      ["{+a*,b*}", "x,y"] => {"a" => ["x", "y"], "b" => nil},
      ["{+a*,b*,c}", "x,y,z"] => {"a" => ["x", "y", "z"], "b" => nil, "c" => nil},
      ["{+a*,b,c*}", "x,y"] => {"a" => ["x", "y"], "b" => nil, "c" => nil},
      ["{+a*,b}z", "x,yz"] => {"a" => ["x", "y"], "b" => nil},
      # (A name used twice isn't split this way.)
      ["{#a*,c*,b,b}/-", "#k=a;b,n=a,a=b,a=b/-"] => {
        "a" => ["k=a;b", "n=a", "a=b"], "c" => nil, "b" => ""
      },
      ["{;a*,b*}", ";a=1;b=2"] => {"a" => {"a" => "1", "b" => "2"}, "b" => {}},
      # ...for ? and &, unless an empty member comes first...
      ["{?a*,b*}", "?a=1&b=2"] => {"a" => {"a" => "1", "b" => "2"}, "b" => nil},
      # A variable that isn't exploded takes its own pair from them.
      ["{?a*,b*,c}", "?a=1&b=2&c=3"] => {
        "a" => {"a" => "1", "b" => "2"}, "b" => nil, "c" => "3"
      },
      # ...and for /, . and the default operator.
      ["{/a*,b*}", "/x/y"] => {"a" => ["x", "y"], "b" => nil},
      ["{/a*,b*}", "//x/y"] => {"a" => ["", "x", "y"], "b" => nil},
      ["{/a*,b,c*}", "/x/y/z"] => {
        "a" => ["x", "y", "z"], "b" => nil, "c" => nil
      },
      ["{a*,b*}", ",x,y"] => {"a" => ["", "x", "y"], "b" => nil},
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
      ["{a,b}{c*}", "x,y,z"] => {
        "a" => nil, "b" => nil, "c" => ["x", "y", "z"]
      },
      ["{.a}{c*}", ".x,y"] => {"a" => nil, "c" => [".x", "y"]},
      ["{a*}{c,d*}", "x,y"] => {"a" => nil, "c" => "x", "d" => ["y"]},
      # An exploded {+b*} only ends where a run of characters ends.
      ["{+a}{+b*}x", "p,qx"] => {"a" => "p,q", "b" => nil},
      # {b} can't match "/", so {+a} isn't always empty.
      ["{+a}{b}", "p/q"] => {"a" => "p/", "b" => "q"},
      ["{+a}{b}", "p/qr"] => {"a" => "p/", "b" => "qr"},
      ["{#a}{b}", "#p/q"] => {"a" => "p/", "b" => "q"},
      # In + and # expressions, the earlier variables take one value each,
      # and the last one takes the rest, commas and all.
      ["{+v1,v2,v3}", "a"] => {"v1" => "a", "v2" => nil, "v3" => nil},
      ["{+v1,v2,v3}", "a,b"] => {"v1" => "a", "v2" => "b", "v3" => nil},
      ["{+v1,v2,v3}", "a,b,c,d"] => {
        "v1" => "a", "v2" => "b", "v3" => "c,d"
      },
      ["{+v1,v2,v3}x", "a,bx"] => {"v1" => "a", "v2" => "b", "v3" => nil},
      ["{+a,b}", "x,y"] => {"a" => "x", "b" => "y"},
      ["{\#a,b}", "\#x,y,z"] => {"a" => "x", "b" => "y,z"},
      ["{+v1,v2,v3}x", "a,b,x"] => {"v1" => "a", "v2" => "b", "v3" => ""},
      ["{#v1,v2}", "#,b"] => {"v1" => "", "v2" => "b"},
      ["{+v1,v2},x", "a,b,x"] => {"v1" => "a", "v2" => "b"},
      # A repeated name keeps its first value.
      ["{+v1,v2,v1}", "a,b,c"] => {"v1" => "a", "v2" => "b"},
      ["{+a,b},x", "p,x"] => {"a" => "p", "b" => nil},
      ["{+a,b},x", "p,q,x"] => {"a" => "p", "b" => "q"},
      # An exploded ;, ? or & value is an associative array, which keeps
      # everything after each value's first "=", and keeps a repeated key's
      # last value.
      ["{;b*}", ";b==a"] => {"b" => {"b" => "=a"}},
      ["{;a*}", ";a=b=c;d"] => {"a" => {"a" => "b=c", "d" => ""}},
      ["{&b*}", "&k=ab%3Bb="] => {"b" => {"k" => "ab;b="}},
      ["{?a*}", "?a=b=c&d=e"] => {"a" => {"a" => "b=c", "d" => "e"}},
      ["{?a*}", "?a=bc=d"] => {"a" => {"a" => "bc=d"}},
      ["{;b*,c*}", ";n=ak=ab;c=a2Cb"] => {
        "b" => {"n" => "ak=ab", "c" => "a2Cb"}, "c" => {}
      },
      ["{?a*,a*,a*}", "?a=aba=ab&a=ab"] => {"a" => {"a" => "ab"}},
      ["{?a*,c*}", "?a=b=c&d=e"] => {
        "a" => {"a" => "b=c", "d" => "e"}, "c" => nil
      },
      ["{&a*}{&b}", "&x=1=2&b=3"] => {
        "a" => {"x" => "1=2", "b" => "3"}, "b" => nil
      },
      ["{;a*}{?b*}", ";a=1;b?c=d=e"] => {
        "a" => {"a" => "1", "b" => ""}, "b" => {"c" => "d=e"}
      },
      # For ? and &, an empty member before the first exploded variable's
      # values gives them to the next one.
      ["{?a*,b*}", "?&b=2"] => {"a" => nil, "b" => {"b" => "2"}},
      ["{&a*,b*}", "&&b=2"] => {"a" => nil, "b" => {"b" => "2"}},
      ["{?a*,b,c*}", "?&=="] => {"a" => nil, "b" => nil, "c" => {"" => "="}},
      # An exploded /, . or default variable before unexploded ones takes
      # every member, and the later variables are undefined.
      ["{/a*,b,c}x", "/p/q/rx"] => {"a" => ["p", "q", "r"], "b" => nil, "c" => nil},
      # A plain expression can't contain "=", so the value before it isn't
      # committed to.
      ["{+a}={c}", "p=q=r"] => {"a" => "p=q", "c" => "r"},
      ["{+a}{b,c}", "x/yz,w"] => {"a" => "x/", "b" => "yz", "c" => "w"},
      # A value that can contain the literal text after it takes it where the
      # rest of the URI can still match.
      ["/{+path}.{format}", "/docs/v1.2/guide.html"] => {
        "path" => "docs/v1.2/guide", "format" => "html"
      },
      ["/{+prefix}-{id}", "/a-b/c-9"] => {"prefix" => "a-b/c", "id" => "9"},
      ["/files/{+name}_{rev}", "/files/x_y/z_3"] => {
        "name" => "x_y/z", "rev" => "3"
      },
      ["{+base}{/owner,repo}", "example.com/git/foo/bar"] => {
        "base" => "example.com/git", "owner" => "foo", "repo" => "bar"
      },
      ["/api{/version}{/resource}.{format}", "/api/users.json"] => {
        "version" => nil, "resource" => "users", "format" => "json"
      },
      ["{+a}\#{b}", "#/%23"] => {"a" => "#/", "b" => nil},
      ["{+a}\#{b}\#{c}", "%23x#y"] => {"a" => nil, "b" => "x", "c" => "y"},
      ["{?a*}={+b,c}=", "?=="] => {"a" => nil, "b" => nil, "c" => nil},
      ["{a*,b*},{#c}{;d}", ",,"] => {
        "a" => ["", ""], "b" => nil, "c" => nil, "d" => nil
      },
      ["/{.a}{.b*}?{.c*,d*}.", "/?.."] => {
        "a" => nil, "b" => nil, "c" => [""], "d" => nil
      },
      # An exploded + or # value can't end before literal text that its
      # members could contain.
      ["{+a}-{+d*}-", "x--"] => {"a" => "x", "d" => nil},
      ["{#d*}/", "#/"] => {"d" => nil},
      ["{+a}{+b*}{/c}.", "x,y/z."] => {"a" => "x,y", "b" => nil, "c" => "z"},
      # An exploded + or # value before an unexploded one takes every
      # member up to the literal text after the expression.
      ["{+d}\#{+b*,c}&", "x#y,z#w&"] => {"d" => "x", "b" => ["y", "z#w"], "c" => nil},
      ["{+d}\#{+b*,c}&", "x#y#z&"] => {"d" => "x", "b" => ["y#z"], "c" => nil},
      # Literal text that nothing after it can contain is the last of its
      # character in the URI.
      ["/{+a,b,c}/{+c,a}{/a},{;c};", "/x,y/p,q/r,;c=1;"] => {
        "a" => "x", "b" => "y/p", "c" => "q"
      }
    }.each do |(pattern, uri), mapping|
      it "matches #{uri.inspect} against #{pattern}" do
        expect(Addressable::Template.new(pattern).match(uri).mapping).to eq(
          mapping
        )
      end
    end

    {
      # Literal text with a non-ASCII character can also be pct-encoded, and
      # the value before it can end in the same characters.
      ["{a}é{&b}", "x%C3%A9%C3%A9&b=y"] => {"a" => "xé", "b" => "y"},
      ["{d,a}é{&a,d}", "%2B,%C3%A9%C3%A9&a=%C3%A9&d=%2B"] => {
        "d" => "+", "a" => "é"
      },
      # The first of several + variables can be skipped, so it can't take
      # text in front of it.
      ["-{+c}é{+d,a*}~", "-#%C3%A9;;%C3%A9~"] => {
        "c" => "#é;;", "d" => nil, "a" => nil
      },
      # A name in two expressions must get the same value from both.
      [".{#b,c}{&c,a,b}.", ".#x,y&c=y&a=%3B."] => {
        "b" => "x", "c" => "y", "a" => ";"
      }
    }.each do |(pattern, uri), mapping|
      it "matches #{uri.inspect} against #{pattern} with either regexp" do
        open = Addressable::Template.new(pattern)
        open.define_singleton_method(:linear_time?) { |_| true }
        committed = TemplateMatchSpec.committed(
          Addressable::Template.new(pattern)
        )
        expect(open.match(uri).mapping).to eq(mapping)
        expect(committed.match(uri).mapping).to eq(mapping)
      end
    end

    TemplateMatchSpec::OPERATORS.product(["", "*"]).each do |operator, modifier|
      pattern = "{#{operator}a#{modifier}}"
      # A lone label variable at the end of a template takes every character
      # up to the end, so it's compared where it doesn't end the template.
      pattern += "a" if operator == "." && modifier == ""
      it "tries the reference's end positions in its order for #{pattern}" do
        reference = TemplateMatchSpec.unanchored(
          TemplateMatchSpec.reference_regexp(pattern)
        )
        current = TemplateMatchSpec.unanchored(
          TemplateMatchSpec.regexp(pattern)
        )
        alphabet = TemplateMatchSpec.alphabet(operator)
        TemplateMatchSpec.strings(alphabet, 5).each do |string|
          expect(TemplateMatchSpec.end_positions(current, string)).to eq(
            TemplateMatchSpec.end_positions(reference, string)
          ), "for #{string.inspect}"
        end
      end
    end

    TemplateMatchSpec::OPERATORS.each do |operator|
      [
        "{#{operator}a,b,c}", "{#{operator}a,b*}", "{#{operator}a*,b}",
        "{#{operator}a,b}x", "{#{operator}a,b}{#{operator}c}",
        "{#{operator}a*,b*}", "{#{operator}a*,b*,c*}", "{#{operator}a*,b,c*}",
        "{#{operator}a,b*,c*}", "{#{operator}a*,b*,c}",
        "{#{operator}a*,c*,b,b}", "{#{operator}a*,b}x", "{#{operator}a*,b*}x",
        "{#{operator}a*,b,c}x",
        "{#{operator}a}{+b}", "{#{operator}a,b*}{+c}", "{#{operator}a}{b}",
        "{#{operator}a*}{b}{+c}", "{#{operator}a}{+b}x",
        "{#{operator}a,b,c}x", "{#{operator}a,b},x", "{#{operator}a,b,a}",
        "{#{operator}a,b:2,c}/", "{#{operator}a,b}{+c,d}",
        "{#{operator}a}{c*}", "{#{operator}a,b}{c,d*}", "{#{operator}a}{+c*}x",
        "{#{operator}a,b}{c,d}"
      ].each do |pattern|
        it "captures the same values as the reference for #{pattern}" do
          reference = TemplateMatchSpec.reference_regexp(pattern)
          current = TemplateMatchSpec.regexp(pattern)
          alphabet = TemplateMatchSpec.alphabet(operator, "x")
          TemplateMatchSpec.strings(alphabet, 5).each do |string|
            next if TemplateMatchSpec.committed?(pattern, operator, string)
            expected = reference.match(string)
            actual = current.match(string)
            expect(TemplateMatchSpec.named_captures(actual)).to eq(
              TemplateMatchSpec.named_captures(expected)
            ), "for #{string.inspect}"
          end
        end
      end
    end

    [
      "/{+path}.{format}", "{+a}\#{b}\#{c}", "{+base}\#{a}", "{a,b}.{c}",
      "{+a}/{b}{/c*}", "{+a}-{+d*}-", "{#b*,c},{#d,c,a*};", "{a*,b*},{#c}{;d}",
      "/{.a}{.b*}?{.c*,d*}.", "{?a*}={+b,c}=", "/{year}-{month}-{day}",
      "{+a}/{b}-{+c}", "{.a*,b*,c}", "{a*}{.a*,b*,c}", "{+v1,v2,v3},{+d}"
    ].each do |pattern|
      it "gives the same values whether or not it commits for #{pattern}" do
        template = Addressable::Template.new(pattern)
        open = template.send(
          :parse_new_template_pattern, pattern, nil, nil, false
        )[1]
        allow(template).to receive(:linear_time?).and_return(false)
        committed = template.send(
          :parse_new_template_pattern, pattern, nil, nil, true
        )[1]
        expect(committed).not_to eq(open)
        alphabet = ["a", "/", ".", "-", ",", "#", "%23", "?", "=", ";"]
        TemplateMatchSpec.strings(alphabet, 4).each do |string|
          expect(TemplateMatchSpec.named_captures(committed.match(string))).to eq(
            TemplateMatchSpec.named_captures(open.match(string))
          ), "for #{string.inspect}"
        end
      end
    end

    it "keeps every choice open where the engine matches in linear time" do
      template = Addressable::Template.new("/{year}-{month}-{day}")
      allow(template).to receive(:linear_time?).and_return(true)
      stub_const("Addressable::Template::LINEAR_TIME_CHECKED", true)
      regexp = template.send(:parse_new_template_pattern, template.pattern)[1]
      expect(regexp).to eq(template.send(
        :parse_new_template_pattern, template.pattern, nil, nil, false
      )[1])
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

    it "gives the later of adjacent expressions the value with a processor" do
      processor = Object.new
      def processor.match(name)
        nil
      end
      template = Addressable::Template.new("{+a}{+b}")
      expect(template.match("xy", processor).mapping).to eq(
        "a" => nil, "b" => "xy"
      )
    end

    it "keeps every choice open when a processor gives a pattern" do
      processor = Object.new
      def processor.match(name)
        name == "id" || name == "c" ? "[0-9]+" : nil
      end
      expect(
        Addressable::Template.new("/{slug}-{id}").
          match("/my-post-title-123", processor).mapping
      ).to eq("slug" => "my-post-title", "id" => "123")
      expect(
        Addressable::Template.new("{+a,b}{c}").match("x,yz12", processor).mapping
      ).to eq("a" => "x", "b" => "yz", "c" => "12")
    end

    it "commits to choices with a processor that gives no patterns" do
      processor = Object.new
      def processor.match(name)
        nil
      end
      template = Addressable::Template.new("/{year}-{month}-{day}")
      expect do
        Timeout.timeout(10) do
          expect(template.match("/" + ("-" * 4000) + "!", processor)).to be_nil
        end
      end.not_to raise_error
      expect(template.match("/2024-01-02", processor).mapping).to eq(
        "year" => "2024", "month" => "01", "day" => "02"
      )
    end

    it "matches the other variables around a processor's pattern" do
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

  context "when an expression has several variables" do
    # Expanding a match gives the matched text back, and each variable,
    # from the first, takes as much as it can: an exploded variable every
    # member left, and another variable one member, except the last
    # variable of a + or # expression, which takes the rest.
    it "reads the values back from the first variable" do
      rng = Random.new(6570)
      wrong = []
      400.times do
        operator = [nil, "+", "#", "/", "."].sample(random: rng)
        names = %w(a b c).first(rng.rand(2..3))
        varspecs = names.map { |name| rng.rand(2) == 0 ? "#{name}*" : name }
        template = Addressable::Template.new("{#{operator}#{varspecs.join(',')}}")
        mapping = {}
        varspecs.each do |varspec|
          next if rng.rand(4) == 0
          members = Array.new(rng.rand(1..3)) { ["x", "y", "", "z1"].sample(random: rng) }
          mapping[varspec.delete("*")] = varspec.end_with?("*") ? members : members.first
        end
        uri = template.expand(mapping).to_s
        extracted = template.extract(uri)
        if extracted.nil? || template.expand(extracted).to_s != uri
          wrong << [template.pattern, uri, extracted]
          next
        end
        joiner = {"/" => "/", "." => "."}.fetch(operator, ",")
        text = uri.sub(/\A[#\/.]/, "")
        members = uri.empty? ? [] : text.split(joiner, -1)
        members = [""] if !uri.empty? && members.empty?
        expected = varspecs.each_with_index.map do |varspec, position|
          name = varspec.delete("*")
          value = if members.empty?
            nil
          elsif varspec.end_with?("*")
            members.slice!(0..-1)
          elsif position == varspecs.size - 1 && ["+", "#"].include?(operator)
            members.slice!(0..-1).join(joiner)
          else
            members.shift
          end
          [name, value]
        end.to_h
        wrong << [template.pattern, uri, extracted, expected] if extracted != expected
      end
      expect(wrong.first(5)).to eq([])
    end
  end

  context "when the template has no ASCII literal text" do
    # The regexp that commits to choices rejects up front a URI with an
    # ASCII character that nothing in the template can contain. Here that's
    # every ASCII character, so only pct-encoded triplets and non-ASCII text
    # are left.
    {
      "" => { matches: [""], rejects: ["x", "%41"] },
      "é" => { matches: ["é"], rejects: ["e", "éx", ""] },
      "中" => { matches: ["中"], rejects: ["x", "中中"] },
      "é中" => { matches: ["é中"], rejects: ["é", "x"] }
    }.each do |pattern, uris|
      [:own, :committed].each do |which|
        it "matches URIs against #{pattern.inspect} with the #{which} regexp" do
          template = Addressable::Template.new(pattern)
          template = TemplateMatchSpec.committed(template) if which == :committed
          uris[:matches].each do |uri|
            expect(template.match(uri)).not_to be_nil, "#{uri.inspect} didn't match"
            expect(template.extract(uri)).to eq({})
          end
          uris[:rejects].each do |uri|
            expect(template.match(uri)).to be_nil, "#{uri.inspect} matched"
          end
        end
      end
    end
  end

  context "with adversarial input" do
    # A shorter payload for these where the template commits to choices, as
    # it does where the regular expression engine can't match the regexp
    # that keeps every choice open in linear time, to keep slow runners
    # within the time limit. It is still long enough for backtracking that
    # grows exponentially to time out.
    committed_payloads = {
      "{+d}{/d,c*}\#{+b*,c,a*}&{?c*}" => ("/a%23" * 2000) + " ",
      ",{c*,d*,a*},{+a*,d,b*}.json" => ("," * 250) + "?.json"
    }
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
      "{+foo*,bar*}" => ("a," * 5000) + " ",
      "{+foo*,bar*,baz*}" => ("a," * 2000) + " ",
      "{#foo*,bar*,baz*}" => "#" + ("a," * 2000) + " ",
      "{+foo*,bar*,baz}" => ("a," * 2000) + " ",
      "{+foo*,bar,baz*}" => ("a," * 2000) + " ",
      "{;foo*,bar*,baz*}" => ";" + ("a=1;" * 2000) + "!",
      "{/foo*,bar*,baz*}" => "/" + ("a/" * 2000) + "!",
      "{/foo*,bar,baz*}" => "/" + ("a/" * 2000) + "!",
      "{.foo*,bar*}" => "." + ("a." * 2000) + "!",
      "{foo*,bar*,baz*}" => ("a," * 2000) + "!",
      "{?foo*,bar*}" => "?" + ("a=1&" * 2000) + " ",
      "{?foo*,bar*,baz*}" => "?" + ("a=1&" * 2000) + " ",
      "{&foo*,bar*,baz*}" => "&" + ("a=1&" * 2000) + " ",
      "{?foo*,bar*,baz}" => "?" + ("a=1&" * 2000) + " ",
      "{?foo,bar*,baz*}" => "?" + ("a=1&" * 2000) + " ",
      "{?foo*,bar*} (empty members)" => "?" + ("a=&&" * 2000) + " ",
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
      "{.a,b}{c,d*}" => "." + ("a" * 4000) + "!",
      "{+a,c,c,c}" => ("," * 4000) + " ",
      "{+v1,v2,v3,v4,v5,v6,v7,v8}{c*}" => ("," * 8000) + " ",
      "{+a,b,c},{+d}" => ("," * 16_000) + " ",
      "{a*}{.a*,b*,c}" => ("." * 4000) + " ",
      "{a*}{.a*,b*,c}." => ("." * 4000) + " ",
      "{.a*,b*,c}" => ("." * 24_000) + " ",
      "{?a*,b,c*}" => "?" + ("a=a&b=b&" * 8000) + " ",
      "{?a,a*,a*}{a*}{.a*,b*,c}" => ("." * 4000) + " ",
      "{d*,b,a}-" => (".--" * 12_000) + " ",
      "/{year}-{month}-{day}" => "/" + ("-" * 4000) + "!",
      "/v{major}.{minor}.{patch}" => "/v" + ("." * 4000) + "!",
      "{+base}/{+path}/{+file}" => ("/" * 4000) + " ",
      "/{year}-{month}-{day}/{a}{b}" => "/" + ("-" * 4000) + "!",
      "/{year}-{month}-{day}{/a,b}" => "/" + ("-" * 4000) + "!",
      "{+a}/{b}-{+c}" => ("/b-" * 32_000) + " ",
      "{+a}/{b}{/c*}" => ("/b/" * 16_000) + " ",
      "{+a}/{b,c}/{+d}" => ("/b," * 24_000) + " ",
      "{+a}\#{b}\#{c}" => ("%23" * 20_000) + " ",
      "{+a}\#{b}\#{c}/x/" => ("%23" * 4000) + " ",
      "{+a}\#{b}/x/{c}" => ("%23" * 20_000) + " ",
      "{+base}\#{a}" => ("%23" * 50_000) + " ",
      "{a,b}{c}" => ("a" * 60_000) + "!",
      "{a,b}{c,d}{e,f}" => ("a" * 2000) + "!",
      "{+a}{b,c}" => ("a" * 60_000) + " ",
      "/{+path}.{format}" => "/" + ("." * 8000) + "/-",
      "{+base}{/owner,repo}" => ("/" * 8000) + " ",
      "/files/{+name}_{rev}" => "/files/" + ("_/" * 8000) + " ",
      "{a,b}.{c}" => ("." * 8000) + ",",
      "{+a}\#{b}" => "#" + ("%23" * 8000) + "/",
      "{+a}-{+d*}-" => ("-," * 8000) + "-",
      "{#b*,c},{#d,c,a*};" => ("#,#" * 8000) + ";;",
      "{?a*}={+b,c}=" => "?" + ("=" * 8000) + "&=",
      "{+a}{+b*}{/c}." => ("=+." * 8000) + " ",
      "/{+a,b,c}/{+c,a}{/a},{;c};" => "/" + ("/,?" * 8000) + " ",
      "{+d}\#{+b*,c}&{?x*}" => ("?%23" * 8000) + " ",
      "{+d}{/d,c*}\#{+b*,c,a*}&{?c*}" => ("/a%23" * 8000) + " ",
      "{+d}{/d,c*}\#{+b*,c,a*}&{?c*} (no member ends)" =>
        ("%23/" * 1000) + "&",
      "{+b,c*,a},{/c,a*}{+c*,b};{\#b,d}" => ("," * 2000) + " ",
      "{.b,a}{b*,c,d}{d*,a}/x/{/d*,b*,a*}/x/" => ("," * 2000) + "/x/a/x/",
      ",{c*,d*,a*},{+a*,d,b*}.json" => ("," * 1000) + "?.json"
    }.each do |name, long_payload|
      template = Addressable::Template.new(name.split(" ").first)
      suffix = template.pattern[/[^}]*\z/]
      # The payload as it is, and ending in each character that the
      # template could match instead, alone and before the literal text
      # that ends the template, so that it can't be rejected just for that.
      endings = ["", "/", "?", "#", ":", ",", ".", "=", "&", ";", "-", "%"]
      variants = lambda do |payload|
        [payload] + endings.flat_map do |ending|
          base = payload.sub(/[ !]\z/, "") + ending
          suffix.empty? ? [base] : [base, base + suffix]
        end
      end
      committed_payload = committed_payloads.fetch(name, long_payload)
      long = "a long payload for #{name} in linear time"
      committed_description =
        committed_payloads.key?(name) ? "a shorter payload for #{name}" : long
      # The template commits to choices itself where the engine can't match
      # the regexp that keeps every choice open in linear time.
      commits = committed_payloads.key?(name) &&
        template.to_regexp == TemplateMatchSpec.committed(
          Addressable::Template.new(template.pattern)
        ).to_regexp
      payload, description =
        if commits
          [committed_payload, committed_description]
        else
          [long_payload, long]
        end

      it "matches #{description}", regexp_timing: true do
        expect do
          Timeout.timeout(10) do
            variants.call(payload).each { |variant| template.match(variant) }
          end
        end.not_to raise_error
      end

      it "matches #{committed_description} when it commits to choices",
          regexp_timing: true do
        committed = TemplateMatchSpec.committed(
          Addressable::Template.new(template.pattern)
        )
        expect do
          Timeout.timeout(10) do
            variants.call(committed_payload).each do |variant|
              committed.match(variant)
            end
          end
        end.not_to raise_error
      end

      next unless payload =~ /[ !]\z/

      it "rejects the long payload for #{name}" do
        expect(template.match(payload)).to be_nil
      end
    end
  end
end
