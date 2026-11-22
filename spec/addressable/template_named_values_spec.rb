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

require "addressable/template"

# In ;, ? and & expansion, a variable that isn't exploded expands to its own
# name, "=" and its value (RFC 6570 sections 3.2.7 to 3.2.9). Matching reads
# a pair as that variable's only when the name is the variable's, wherever
# the pair is in the expression.
describe Addressable::Template, "matching the names of ;, ? and & variables" do
  def extract(pattern, uri, processor = nil)
    Addressable::Template.new(pattern).extract(uri, processor)
  end

  context "with a name the expression doesn't have" do
    {
      ["/search{?q}", "/search?admin=true"] => nil,
      ["/search{?q,page}", "/search?q=x&admin=true"] => nil,
      ["/files{;version}/{id}", "/files;id=secret/42"] => nil,
      ["/search{?q}{&page}", "/search?page=9&page=1"] => nil,
      ["{&q}", "&admin=1"] => nil,
      ["{;x,y}", ";z=1"] => nil,
      ["{?q}", "?Q=x"] => nil,
      ["{?a}", "?%61=x"] => nil
    }.each do |(pattern, uri), mapping|
      it "doesn't match #{uri} against #{pattern}" do
        expect(extract(pattern, uri)).to eq(mapping)
      end
    end
  end

  context "with the expression's own names" do
    {
      ["/search{?q}", "/search?q=x"] => {"q" => "x"},
      ["/search{?q}", "/search?q="] => {"q" => ""},
      ["/search{?q}", "/search"] => {"q" => nil},
      ["/search{?q,page}", "/search?q=x&page=2"] => {"q" => "x", "page" => "2"},
      ["/search{?q,page}", "/search?page=2&q=x"] => {"q" => "x", "page" => "2"},
      ["/search{?q,page}", "/search?page=2"] => {"q" => nil, "page" => "2"},
      ["{?a,b,c}", "?c=3&a=1&b=2"] => {"a" => "1", "b" => "2", "c" => "3"},
      ["{&x,y}", "&y=2&x=1"] => {"x" => "1", "y" => "2"},
      ["/search{?q}{&page}", "/search?q=a&page=1"] => {"q" => "a", "page" => "1"},
      ["{?a,b}{&c}", "?a=1&c=2"] => {"a" => "1", "b" => nil, "c" => "2"},
      ["/files{;version}/{id}", "/files;version=2/42"] => {
        "version" => "2", "id" => "42"
      },
      ["{;x,y}", ";x;y=2"] => {"x" => "", "y" => "2"},
      ["{;x,y}", ";y=2;x"] => {"x" => "", "y" => "2"},
      ["{;x,y}", ";y=2"] => {"x" => nil, "y" => "2"},
      ["{?x:2}", "?x=he"] => {"x" => "he"},
      ["{?a.b}", "?a.b=1"] => {"a.b" => "1"},
      ["{?a%20b}", "?a%20b=1"] => {"a%20b" => "1"},
      ["{?a%2Cb}", "?a%2cb=1"] => {"a%2Cb" => "1"},
      ["{?q,qq}", "?qq=2&q=1"] => {"q" => "1", "qq" => "2"},
      ["{;q,qq}", ";qq;q"] => {"q" => "", "qq" => ""},
      ["{;q,qq}", ";qq"] => {"q" => nil, "qq" => ""},
      ["{?q}", "?q=a%26b"] => {"q" => "a&b"}
    }.each do |(pattern, uri), mapping|
      it "matches #{uri} against #{pattern}" do
        expect(extract(pattern, uri)).to eq(mapping)
      end
    end
  end

  context "with a name given twice" do
    {
      ["{?q}", "?q=cat&q=dog"] => nil,
      ["{?q,page}", "?q=cat&q=dog"] => nil,
      ["{;x,y}", ";x=1;x=2"] => nil,
      ["{?q,list*}", "?q=cat&x=1&q=dog"] => nil
    }.each do |(pattern, uri), mapping|
      it "doesn't match #{uri} against #{pattern}" do
        expect(extract(pattern, uri)).to eq(mapping)
      end
    end
  end

  context "next to an exploded variable" do
    {
      ["/search{?q,list*}", "/search?page=1&q=cat&per-page=10"] => {
        "q" => "cat", "list" => {"page" => "1", "per-page" => "10"}
      },
      ["/search{?q,list*}", "/search?q=cat&page=1&per-page=10"] => {
        "q" => "cat", "list" => {"page" => "1", "per-page" => "10"}
      },
      ["/search{?q,list*}", "/search?page=1"] => {
        "q" => nil, "list" => {"page" => "1"}
      },
      ["/search{?q,list*}", "/search?q=cat"] => {"q" => "cat", "list" => nil},
      # An exploded value is an associative array, which keeps a repeated
      # key's last value.
      ["{?q,tags*}", "?tags=a&q=cat&tags=b"] => {
        "q" => "cat", "tags" => {"tags" => "b"}
      },
      ["{;list*,q}", ";a=1;q=2"] => {"list" => {"a" => "1"}, "q" => "2"}
    }.each do |(pattern, uri), mapping|
      it "matches #{uri} against #{pattern}" do
        expect(extract(pattern, uri)).to eq(mapping)
      end
    end
  end

  context "with a processor" do
    let(:digits) do
      Class.new do
        def self.match(name)
          name == "page" ? "\\d+" : nil
        end
      end
    end

    it "applies a variable's pattern to its value" do
      expect(extract("/search{?q}{&page}", "/search?q=x&page=7", digits)).to eq(
        "q" => "x", "page" => "7"
      )
      expect(extract("/search{?q,page}", "/search?page=7&q=x", digits)).to eq(
        "q" => "x", "page" => "7"
      )
    end

    it "doesn't match a value its pattern doesn't" do
      expect(extract("/search{?q}{&page}", "/search?q=x&page=abc", digits)).to eq(
        nil
      )
      expect(extract("/search{?q}{&page}", "/search?page=abc", digits)).to eq(nil)
      expect(extract("/search{?q,page}", "/search?page=abc&q=1", digits)).to eq(
        nil
      )
    end

    it "checks a value taken from an exploded variable against its pattern" do
      expect(extract("{?page,list*}", "?x=1&page=abc", digits)).to eq(nil)
      expect(extract("{?page,list*}", "?x=1&page=7", digits)).to eq(
        "page" => "7", "list" => {"x" => "1"}
      )
    end

    it "doesn't apply a pattern to the name" do
      named = Class.new do
        def self.match(name)
          name == "page" ? "page=\\d+" : nil
        end
      end
      expect(extract("/search{?q}{&page}", "/search?q=x&page=7", named)).to eq(
        nil
      )
    end

    it "only restores the template's names" do
      calls = []
      recorder = Class.new do
        define_singleton_method(:restore) do |name, value|
          calls << name
          value
        end
      end
      template = Addressable::Template.new(
        "/gallery/{id}{?remaining}"
      )
      expect(
        template.extract("/gallery/real?id=other", recorder)
      ).to eq(nil)
      calls.clear
      expect(
        template.extract("/gallery/real?remaining=x", recorder)
      ).to eq("id" => "real", "remaining" => "x")
      expect(calls.uniq.sort).to eq(["id", "remaining"])
    end
  end

  it "extracts the values that ;, ? and & expansion gives, in any order" do
    random = Random.new(7)
    names = %w[a b c dd e.f]
    values = ["", "x", "1%2C2", "hello", "a-b"]
    1000.times do
      operator = %w[; ? &].sample(random: random)
      varlist = names.sample(random.rand(1..4), random: random)
      template = Addressable::Template.new("{#{operator}#{varlist.join(',')}}")
      mapping = {}
      varlist.each do |name|
        mapping[name] = values.sample(random: random) if random.rand(4) > 0
      end
      uri = template.expand(mapping).to_s
      expected = varlist.each_with_object({}) do |name, result|
        result[name] = mapping[name]
      end
      expect(template.extract(uri)).to eq(expected), "for #{uri}"

      leader = uri[0]
      pairs = uri[1..-1].to_s.split(operator == ";" ? ";" : "&").shuffle(
        random: random
      )
      next if pairs.empty?
      shuffled = leader + pairs.join(operator == ";" ? ";" : "&")
      expect(template.extract(shuffled)).to eq(expected), "for #{shuffled}"
    end
  end
end
