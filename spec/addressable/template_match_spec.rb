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
  UNRESERVED = Addressable::Template::UNRESERVED
  RESERVED_NO_COMMA = Addressable::Template::RESERVED_NO_COMMA

  # The exploded member patterns from Addressable 2.9.0. Members were joined
  # by an optional joiner, except for the default operator.
  LEGACY_MEMBERS = {
    nil => "#{UNRESERVED}*?",
    "+" => "#{RESERVED_NO_COMMA}*+",
    "#" => "#{RESERVED_NO_COMMA}*+",
    "/" => "#{UNRESERVED}*?",
    "." => "#{UNRESERVED.gsub('\.', '')}*?",
    ";" => "#{UNRESERVED}*=?#{UNRESERVED}*?",
    "?" => "#{UNRESERVED}*=#{UNRESERVED}*?",
    "&" => "#{UNRESERVED}*=#{UNRESERVED}*?"
  }

  def self.leader(operator)
    Addressable::Template::LEADERS.fetch(operator, "")
  end

  def self.joiner(operator)
    Addressable::Template::JOINERS.fetch(operator, ",")
  end

  # The regular expression 2.9.0 generated for "{<operator>a*}".
  def self.legacy_expression(operator)
    member = LEGACY_MEMBERS.fetch(operator)
    joiner = Regexp.escape(joiner(operator))
    joiner = "#{joiner}?" unless operator.nil?
    "(?:|#{Regexp.escape(leader(operator))}" \
      "(?<a>#{member}(?:#{joiner}#{member})*)?)"
  end

  # The regular expression generated now for "{<operator>a*}".
  def self.expression(operator)
    pattern = "{#{operator}a*}"
    _, regexp = Addressable::Template.new(pattern).send(
      :parse_template_pattern, pattern
    )
    regexp.source[/\A\\A(.*)\\z\z/m, 1]
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

  # Every string of up to max_length tokens drawn from alphabet.
  def self.strings(alphabet, max_length)
    (0..max_length).flat_map do |length|
      alphabet.repeated_permutation(length).map(&:join)
    end.uniq
  end
end

describe Addressable::Template, "#match with exploded variables" do
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
      ["{a*}{b}", "x,y,z"] => {"a" => ["x,y,"], "b" => "z"}
    }.each do |(pattern, uri), mapping|
      it "matches #{uri.inspect} against #{pattern} as 2.9.0 did" do
        expect(Addressable::Template.new(pattern).match(uri).mapping).to eq(
          mapping
        )
      end
    end

    TemplateMatchSpec::LEGACY_MEMBERS.each_key do |operator|
      it "tries the same end positions in the same order for " \
          "{#{operator}a*}" do
        legacy = TemplateMatchSpec.legacy_expression(operator)
        current = TemplateMatchSpec.expression(operator)
        alphabet = [
          TemplateMatchSpec.leader(operator),
          TemplateMatchSpec.joiner(operator),
          "a", "=", "%41"
        ].reject(&:empty?).uniq
        TemplateMatchSpec.strings(alphabet, 5).each do |string|
          expect(TemplateMatchSpec.end_positions(current, string)).to eq(
            TemplateMatchSpec.end_positions(legacy, string)
          ), "for #{string.inspect}"
        end
      end
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
      "{&foo*}" => "&" + ("a=" * 1000) + "!"
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
