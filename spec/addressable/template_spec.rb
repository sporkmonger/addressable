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

require "bigdecimal"
require "timeout"
require "addressable/template"

shared_examples_for 'expands' do |tests|
  tests.each do |template, expansion|
    exp = expansion.is_a?(Array) ? expansion.first : expansion
    it "#{template} to #{exp}" do
      tmpl = Addressable::Template.new(template).expand(subject)
      expect(tmpl.to_str).to eq(expansion)
    end
  end
end

describe "eql?" do
  let(:template) { Addressable::Template.new('https://www.example.com/{foo}') }
  it 'is equal when the pattern matches' do
    other_template = Addressable::Template.new('https://www.example.com/{foo}')
    expect(template).to be_eql(other_template)
    expect(other_template).to be_eql(template)
  end
  it 'is not equal when the pattern differs' do
    other_template = Addressable::Template.new('https://www.example.com/{bar}')
    expect(template).to_not be_eql(other_template)
    expect(other_template).to_not be_eql(template)
  end
  it 'is not equal to non-templates' do
    uri = 'https://www.example.com/foo/bar'
    addressable_template = Addressable::Template.new uri
    addressable_uri = Addressable::URI.parse uri
    expect(addressable_template).to_not be_eql(addressable_uri)
    expect(addressable_uri).to_not be_eql(addressable_template)
  end
end

describe "hash" do
  let(:template) { Addressable::Template.new('https://www.example.com/{foo}') }
  let(:other_template) do
    Addressable::Template.new('https://www.example.com/{foo}')
  end

  it 'is the same for equal templates' do
    expect(template.hash).to eq(other_template.hash)
  end

  it 'differs when the pattern differs' do
    different = Addressable::Template.new('https://www.example.com/{bar}')
    expect(template.hash).to_not eq(different.hash)
  end

  it 'is the same for an equal template of a subclass' do
    subclassed = Class.new(Addressable::Template).new(template.pattern)
    expect(template).to be_eql(subclassed)
    expect(template.hash).to eq(subclassed.hash)
  end

  it 'is the same after freezing' do
    hash = template.hash
    expect(template.freeze.hash).to eq(hash)
  end

  it 'finds an equal template used as a Hash key' do
    expect({ template => :found }[other_template]).to eq(:found)
  end

  it 'removes equal templates with uniq' do
    expect([template, other_template].uniq).to eq([template])
  end
end

describe "==" do
  let(:template) { Addressable::Template.new('https://www.example.com/{foo}') }
  it 'is equal when the pattern matches' do
    other_template = Addressable::Template.new('https://www.example.com/{foo}')
    expect(template).to eq other_template
    expect(other_template).to eq template
  end
  it 'is not equal when the pattern differs' do
    other_template = Addressable::Template.new('https://www.example.com/{bar}')
    expect(template).not_to eq other_template
    expect(other_template).not_to eq template
  end
  it 'is not equal to non-templates' do
    uri = 'https://www.example.com/foo/bar'
    addressable_template = Addressable::Template.new uri
    addressable_uri = Addressable::URI.parse uri
    expect(addressable_template).not_to eq addressable_uri
    expect(addressable_uri).not_to eq addressable_template
  end
end

describe "#to_regexp" do
  it "does not match the first line of multiline strings" do
    uri = "https://www.example.com/bar"
    template = Addressable::Template.new(uri)
    expect(template.match(uri)).not_to be_nil
    expect(template.match("#{uri}\ngarbage")).to be_nil
  end
end

describe "#match" do
  it "returns nil, rather than raising, for a string that isn't a valid URI" do
    template = Addressable::Template.new("https://{domain}")
    expect { template.match("x;x:x") }.not_to raise_error
    expect(template.match("x;x:x")).to be_nil
  end

  it "still matches a valid URI normally" do
    template = Addressable::Template.new("https://{domain}/{path}")
    match = template.match("https://example.com/foo")
    expect(match.variables).to eq(["domain", "path"])
    expect(match.captures).to eq(["example.com", "foo"])
  end
end

describe "#extract" do
  it "returns nil, rather than raising, for a string that isn't a valid URI" do
    template = Addressable::Template.new("https://{domain}")
    expect { template.extract("x;x:x") }.not_to raise_error
    expect(template.extract("x;x:x")).to be_nil
  end

  it "still extracts from a valid URI normally" do
    template = Addressable::Template.new("https://{domain}/{path}")
    expect(template.extract("https://example.com/foo")).to eq(
      "domain" => "example.com", "path" => "foo"
    )
  end
end

describe "Type conversion" do
  subject {
    {
      :var => true,
      :hello => 1234,
      :nothing => nil,
      :sym => :symbolic,
      :decimal => BigDecimal('1')
    }
  }

  it_behaves_like 'expands', {
    '{var}' => 'true',
    '{hello}' => '1234',
    '{nothing}' => '',
    '{sym}' => 'symbolic',
    '{decimal}' => RUBY_VERSION < '2.4.0' ? '0.1E1' : '0.1e1'
  }
end

describe "Level 1:" do
  subject {
    {:var => "value", :hello => "Hello World!"}
  }
  it_behaves_like 'expands', {
    '{var}' => 'value',
    '{hello}' => 'Hello%20World%21'
  }
end

describe "Level 2" do
  subject {
    {
      :var => "value",
      :hello => "Hello World!",
      :path => "/foo/bar"
    }
  }
  context "Operator +:" do
    it_behaves_like 'expands', {
      '{+var}' => 'value',
      '{+hello}' => 'Hello%20World!',
      '{+path}/here' => '/foo/bar/here',
      'here?ref={+path}' => 'here?ref=/foo/bar'
    }
  end
  context "Operator #:" do
    it_behaves_like 'expands', {
      'X{#var}' => 'X#value',
      'X{#hello}' => 'X#Hello%20World!'
    }
  end
end

describe "Level 3" do
  subject {
    {
      :var => "value",
      :hello => "Hello World!",
      :empty => "",
      :path => "/foo/bar",
      :x => "1024",
      :y => "768"
    }
  }
  context "Operator nil (multiple vars):" do
    it_behaves_like 'expands', {
      'map?{x,y}' => 'map?1024,768',
      '{x,hello,y}' => '1024,Hello%20World%21,768'
    }
  end
  context "Operator + (multiple vars):" do
    it_behaves_like 'expands', {
      '{+x,hello,y}' => '1024,Hello%20World!,768',
      '{+path,x}/here' => '/foo/bar,1024/here'
    }
  end
  context "Operator # (multiple vars):" do
    it_behaves_like 'expands', {
      '{#x,hello,y}' => '#1024,Hello%20World!,768',
      '{#path,x}/here' => '#/foo/bar,1024/here'
    }
  end
  context "Operator ." do
    it_behaves_like 'expands', {
      'X{.var}' => 'X.value',
      'X{.x,y}' => 'X.1024.768'
    }
  end
  context "Operator /" do
    it_behaves_like 'expands', {
      '{/var}' => '/value',
      '{/var,x}/here' => '/value/1024/here'
    }
  end
  context "Operator ;" do
    it_behaves_like 'expands', {
      '{;x,y}' => ';x=1024;y=768',
      '{;x,y,empty}' => ';x=1024;y=768;empty'
    }
  end
  context "Operator ?" do
    it_behaves_like 'expands', {
      '{?x,y}' => '?x=1024&y=768',
      '{?x,y,empty}' => '?x=1024&y=768&empty='
    }
  end
  context "Operator &" do
    it_behaves_like 'expands', {
      '?fixed=yes{&x}' => '?fixed=yes&x=1024',
      '{&x,y,empty}' => '&x=1024&y=768&empty='
    }
  end
end

describe "Level 4" do
  subject {
    {
      :var => "value",
      :hello => "Hello World!",
      :path => "/foo/bar",
      :semi => ";",
      :list => %w(red green blue),
      :keys => {"semi" => ';', "dot" => '.', :comma => ','}
    }
  }
  context "Expansion with value modifiers" do
    it_behaves_like 'expands', {
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{list}' => 'red,green,blue',
      '{list*}' => 'red,green,blue',
      '{keys}' => 'semi,%3B,dot,.,comma,%2C',
      '{keys*}' => 'semi=%3B,dot=.,comma=%2C',
    }
  end
  context "Operator + with value modifiers" do
    it_behaves_like 'expands', {
      '{+path:6}/here' => '/foo/b/here',
      '{+list}' => 'red,green,blue',
      '{+list*}' => 'red,green,blue',
      '{+keys}' => 'semi,;,dot,.,comma,,',
      '{+keys*}' => 'semi=;,dot=.,comma=,',
    }
  end
  context "Operator # with value modifiers" do
    it_behaves_like 'expands', {
      '{#path:6}/here' => '#/foo/b/here',
      '{#list}' => '#red,green,blue',
      '{#list*}' => '#red,green,blue',
      '{#keys}' => '#semi,;,dot,.,comma,,',
      '{#keys*}' => '#semi=;,dot=.,comma=,',
    }
  end
  context "Operator . with value modifiers" do
    it_behaves_like 'expands', {
      'X{.var:3}' => 'X.val',
      'X{.list}' => 'X.red,green,blue',
      'X{.list*}' => 'X.red.green.blue',
      'X{.keys}' => 'X.semi,%3B,dot,.,comma,%2C',
      'X{.keys*}' => 'X.semi=%3B.dot=..comma=%2C',
    }
  end
  context "Operator / with value modifiers" do
    it_behaves_like 'expands', {
      '{/var:1,var}' => '/v/value',
      '{/list}' => '/red,green,blue',
      '{/list*}' => '/red/green/blue',
      '{/list*,path:4}' => '/red/green/blue/%2Ffoo',
      '{/keys}' => '/semi,%3B,dot,.,comma,%2C',
      '{/keys*}' => '/semi=%3B/dot=./comma=%2C',
    }
  end
  context "Operator ; with value modifiers" do
    it_behaves_like 'expands', {
      '{;hello:5}' => ';hello=Hello',
      '{;list}' => ';list=red,green,blue',
      '{;list*}' => ';list=red;list=green;list=blue',
      '{;keys}' => ';keys=semi,%3B,dot,.,comma,%2C',
      '{;keys*}' => ';semi=%3B;dot=.;comma=%2C',
    }
  end
  context "Operator ? with value modifiers" do
    it_behaves_like 'expands', {
      '{?var:3}' => '?var=val',
      '{?list}' => '?list=red,green,blue',
      '{?list*}' => '?list=red&list=green&list=blue',
      '{?keys}' => '?keys=semi,%3B,dot,.,comma,%2C',
      '{?keys*}' => '?semi=%3B&dot=.&comma=%2C',
    }
  end
  context "Operator & with value modifiers" do
    it_behaves_like 'expands', {
      '{&var:3}' => '&var=val',
      '{&list}' => '&list=red,green,blue',
      '{&list*}' => '&list=red&list=green&list=blue',
      '{&keys}' => '&keys=semi,%3B,dot,.,comma,%2C',
      '{&keys*}' => '&semi=%3B&dot=.&comma=%2C',
    }
  end
end
describe "Modifiers" do
  subject {
    {
      :var => "value",
      :semi => ";",
      :year => [1965, 2000, 2012],
      :dom => %w(example com)
    }
  }
  context "length" do
    it_behaves_like 'expands', {
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{var}' => 'value',
      '{semi}' => '%3B',
      '{semi:2}' => '%3B'
    }
  end
  context "explode" do
    it_behaves_like 'expands', {
      'find{?year*}' => 'find?year=1965&year=2000&year=2012',
      'www{.dom*}' => 'www.example.com',
    }
  end
end
describe "Expansion" do
  subject {
    {
      :count => ["one", "two", "three"],
      :dom => ["example", "com"],
      :dub   => "me/too",
      :hello => "Hello World!",
      :half  => "50%",
      :var   => "value",
      :who   => "fred",
      :base  => "http://example.com/home/",
      :path  => "/foo/bar",
      :list  => ["red", "green", "blue"],
      :keys  => {"semi" => ";","dot" => ".",:comma => ","},
      :v     => "6",
      :x     => "1024",
      :y     => "768",
      :empty => "",
      :empty_keys  => {},
      :undef => nil
    }
  }
  context "concatenation" do
    it_behaves_like 'expands', {
      '{count}' => 'one,two,three',
      '{count*}' => 'one,two,three',
      '{/count}' => '/one,two,three',
      '{/count*}' => '/one/two/three',
      '{;count}' => ';count=one,two,three',
      '{;count*}' => ';count=one;count=two;count=three',
      '{?count}' => '?count=one,two,three',
      '{?count*}' => '?count=one&count=two&count=three',
      '{&count*}' => '&count=one&count=two&count=three'
    }
  end
  context "simple expansion" do
    it_behaves_like 'expands', {
      '{var}' => 'value',
      '{hello}' => 'Hello%20World%21',
      '{half}' => '50%25',
      'O{empty}X' => 'OX',
      'O{undef}X' => 'OX',
      '{x,y}' => '1024,768',
      '{x,hello,y}' => '1024,Hello%20World%21,768',
      '?{x,empty}' => '?1024,',
      '?{x,undef}' => '?1024',
      '?{undef,y}' => '?768',
      '{var:3}' => 'val',
      '{var:30}' => 'value',
      '{list}' => 'red,green,blue',
      '{list*}' => 'red,green,blue',
      '{keys}' => 'semi,%3B,dot,.,comma,%2C',
      '{keys*}' => 'semi=%3B,dot=.,comma=%2C',
    }
  end
  context "reserved expansion (+)" do
    it_behaves_like 'expands', {
      '{+var}' => 'value',
      '{+hello}' => 'Hello%20World!',
      '{+half}' => '50%25',
      '{base}index' => 'http%3A%2F%2Fexample.com%2Fhome%2Findex',
      '{+base}index' => 'http://example.com/home/index',
      'O{+empty}X' => 'OX',
      'O{+undef}X' => 'OX',
      '{+path}/here' => '/foo/bar/here',
      'here?ref={+path}' => 'here?ref=/foo/bar',
      'up{+path}{var}/here' => 'up/foo/barvalue/here',
      '{+x,hello,y}' => '1024,Hello%20World!,768',
      '{+path,x}/here' => '/foo/bar,1024/here',
      '{+path:6}/here' => '/foo/b/here',
      '{+list}' => 'red,green,blue',
      '{+list*}' => 'red,green,blue',
      '{+keys}' => 'semi,;,dot,.,comma,,',
      '{+keys*}' => 'semi=;,dot=.,comma=,',
    }
  end
  context "fragment expansion (#)" do
    it_behaves_like 'expands', {
      '{#var}' => '#value',
      '{#hello}' => '#Hello%20World!',
      '{#half}' => '#50%25',
      'foo{#empty}' => 'foo#',
      'foo{#undef}' => 'foo',
      '{#x,hello,y}' => '#1024,Hello%20World!,768',
      '{#path,x}/here' => '#/foo/bar,1024/here',
      '{#path:6}/here' => '#/foo/b/here',
      '{#list}' => '#red,green,blue',
      '{#list*}' => '#red,green,blue',
      '{#keys}' => '#semi,;,dot,.,comma,,',
      '{#keys*}' => '#semi=;,dot=.,comma=,',
    }
  end
  # RFC 6570 section 3.1: literal characters outside the reserved and
  # unreserved sets are pct-encoded as UTF-8, and pct-encoded triplets are
  # copied as they are.
  context "literals" do
    subject { {"var" => "value"} }
    it_behaves_like 'expands', {
      "caf\u00E9/{var}" => 'caf%C3%A9/value',
      "{var}/\u20AC" => 'value/%E2%82%AC',
      "\u{1D11E}{var}" => '%F0%9D%84%9Evalue',
      'x%20y/{var}' => 'x%20y/value',
      'x%20y{var}z%20w' => 'x%20yvaluez%20w',
      'a%2fb/{var}' => 'a%2fb/value',
      'x y/{var}' => 'x%20y/value',
      '50%off/{var}' => '50%25off/value',
      '50%2/{var}' => '50%252/value',
      '{/{var}' => '%7B/value',
      '{var}}' => 'value%7D',
      'a<b>/{var}' => 'a%3Cb%3E/value',
      "http://example.com/{var}?a=b&c=d#e:f@g!$'()*+,;=" =>
        "http://example.com/value?a=b&c=d#e:f@g!$'()*+,;="
    }

    it "keeps literals as they are in a partial expansion" do
      template = Addressable::Template.new("caf\u00E9 {var}/{other}")
      expect(template.partial_expand("var" => "1").pattern).to eq(
        "caf\u00E9 1/{other}"
      )
    end

    it "matches a literal in either form" do
      template =
        Addressable::Template.new("http://example.com/caf\u00E9/{var}")
      [
        "http://example.com/caf%C3%A9/value",
        "http://example.com/caf%c3%a9/value",
        "http://example.com/caf\u00E9/value"
      ].each do |uri|
        expect(template.extract(uri)).to eq("var" => "value")
      end
      expect(template.extract("http://example.com/caf%C3%A8/value")).to eq(nil)
    end

    it "matches a percent sign in either form" do
      template = Addressable::Template.new("/50%off/{var}")
      expect(template.extract("/50%25off/value")).to eq("var" => "value")
      expect(template.extract("/50%off/value")).to eq("var" => "value")
    end

    it "matches braces that don't start an expression as they are" do
      template = Addressable::Template.new("x{a.*}/{var}")
      expect(template.extract("x{a.*}/value")).to eq("var" => "value")
      expect(template.extract("x%7Ba.*%7D/value")).to eq("var" => "value")
      expect(template.extract("x{aZZZ}/value")).to eq(nil)
      template = Addressable::Template.new("x{a(}/{var}")
      expect(template.extract("x{a(}/value")).to eq("var" => "value")
    end

    it "extracts the values from an expansion" do
      rng = Random.new(1741)
      literals = ["a", "/", "?", "&", "=", "%", "%2F", " ", "\u00E9",
        "\u20AC", "<", "{", "}", "|"]
      operators = ["", "+", "#", ".", "/", ";", "?", "&"]
      valid = /\A(?:[#{
        Addressable::URI::CharacterClasses::RESERVED_AND_UNRESERVED
      }]|%[0-9A-Fa-f]{2})*\z/
      wrong = []
      2000.times do |index|
        names = []
        pattern = "".dup
        rng.rand(1..3).times do
          pattern << Array.new(rng.rand(0..3)) do
            literals.sample(random: rng)
          end.join
          name = "v#{names.size}"
          names << name
          pattern << "{#{operators.sample(random: rng)}#{name}}"
          pattern << "Z"
        end
        pattern << Array.new(rng.rand(0..3)) { literals.sample(random: rng) }.join
        mapping = {}
        names.each { |name| mapping[name] = "x#{rng.rand(100)}" }
        template = Addressable::Template.new(pattern)
        expanded = template.expand(mapping).to_s
        # Random literals can form expressions of their own, such as {a}.
        extracted = template.extract(expanded)
        extracted = extracted &&
          extracted.select { |name, _| names.include?(name) }
        if expanded !~ valid || extracted != mapping
          wrong << [pattern, expanded, extracted]
        end
      end
      expect(wrong.first(5)).to eq([])
    end
  end

  # RFC 6570 section 3.2.3: reserved and fragment expansion pass
  # pct-encoded triplets through, and encode any other "%".
  context "pct-encoded triplets" do
    subject {
      {
        "id" => "admin%2F",
        "not_pct" => "%foo",
        "short" => "50%2",
        "lower" => "a%2fb",
        "list" => ["red%25", "%2Fgreen", "blue "],
        "keys" => {"key1" => "val1%2F", "key%3A" => "%zz"}
      }
    }
    it_behaves_like 'expands', {
      '{+id}' => 'admin%2F',
      '{#id}' => '#admin%2F',
      '{id}' => 'admin%252F',
      '{/id}' => '/admin%252F',
      '{?id}' => '?id=admin%252F',
      '{+not_pct}' => '%25foo',
      '{#not_pct}' => '#%25foo',
      '{not_pct}' => '%25foo',
      '{+short}' => '50%252',
      '{+lower}' => 'a%2fb',
      '{+list}' => 'red%25,%2Fgreen,blue%20',
      '{#list}' => '#red%25,%2Fgreen,blue%20',
      '{+list*}' => 'red%25,%2Fgreen,blue%20',
      '{list}' => 'red%2525,%252Fgreen,blue%20',
      '{+keys}' => 'key1,val1%2F,key%3A,%25zz',
      '{#keys*}' => '#key1=val1%2F,key%3A=%25zz',
      '{keys}' => 'key1,val1%252F,key%253A,%25zz',
      '{+id:6}' => 'admin%2F',
      '{+list:4}' => 'red%25,%2Fgre,blue',
      '{list:4}' => 'red%25,%252Fg,blue',
      '{+id:5}' => 'admin',
      '{#not_pct:2}' => '#%25f',
      '{id:6}' => 'admin%25'
    }

    it "leaves an expanded value as it is when expanding it again" do
      rng = Random.new(1203)
      alphabet = ["%", "%", "2", "F", "f", "a", "Z", "/", "?", "#", "[",
        " ", ",", "~", "\u00E9", "\u20AC", "<", "^"]
      reserved = Addressable::Template.new("{+value}")
      fragment = Addressable::Template.new("{#value}")
      wrong = []
      3000.times do
        value = Array.new(rng.rand(0..8)) { alphabet.sample(random: rng) }.join
        expanded = reserved.expand("value" => value).to_s
        unless expanded =~ /\A(?:[#{
            Addressable::URI::CharacterClasses::RESERVED_AND_UNRESERVED
          }]|%[0-9A-Fa-f]{2})*\z/
          wrong << [value, expanded]
        end
        if reserved.expand("value" => expanded).to_s != expanded
          wrong << [value, expanded]
        end
        if fragment.expand("value" => value).to_s != "#" + expanded
          wrong << [value, expanded]
        end
        # Decoding gives the value back, reading a "%" that doesn't start a
        # pct-encoded triplet as itself.
        decoded = Addressable::URI.unencode(
          value.gsub(/%(?![0-9A-Fa-f]{2})/, "%25")
        )
        if Addressable::URI.unencode(expanded) != decoded
          wrong << [value, expanded]
        end
      end
      expect(wrong.first(5)).to eq([])
    end
  end
  context "label expansion (.)" do
    it_behaves_like 'expands', {
      '{.who}' => '.fred',
      '{.who,who}' => '.fred.fred',
      '{.half,who}' => '.50%25.fred',
      'www{.dom*}' => 'www.example.com',
      'X{.var}' => 'X.value',
      'X{.empty}' => 'X.',
      'X{.undef}' => 'X',
      'X{.var:3}' => 'X.val',
      'X{.list}' => 'X.red,green,blue',
      'X{.list*}' => 'X.red.green.blue',
      'X{.keys}' => 'X.semi,%3B,dot,.,comma,%2C',
      'X{.keys*}' => 'X.semi=%3B.dot=..comma=%2C',
      'X{.empty_keys}' => 'X',
      'X{.empty_keys*}' => 'X'
    }
  end
  context "path expansion (/)" do
    it_behaves_like 'expands', {
      '{/who}' => '/fred',
      '{/who,who}' => '/fred/fred',
      '{/half,who}' => '/50%25/fred',
      '{/who,dub}' => '/fred/me%2Ftoo',
      '{/var}' => '/value',
      '{/var,empty}' => '/value/',
      '{/var,undef}' => '/value',
      '{/var,x}/here' => '/value/1024/here',
      '{/var:1,var}' => '/v/value',
      '{/list}' => '/red,green,blue',
      '{/list*}' => '/red/green/blue',
      '{/list*,path:4}' => '/red/green/blue/%2Ffoo',
      '{/keys}' => '/semi,%3B,dot,.,comma,%2C',
      '{/keys*}' => '/semi=%3B/dot=./comma=%2C',
    }
  end
  context "path-style expansion (;)" do
    it_behaves_like 'expands', {
      '{;who}' => ';who=fred',
      '{;half}' => ';half=50%25',
      '{;empty}' => ';empty',
      '{;v,empty,who}' => ';v=6;empty;who=fred',
      '{;v,bar,who}' => ';v=6;who=fred',
      '{;x,y}' => ';x=1024;y=768',
      '{;x,y,empty}' => ';x=1024;y=768;empty',
      '{;x,y,undef}' => ';x=1024;y=768',
      '{;hello:5}' => ';hello=Hello',
      '{;list}' => ';list=red,green,blue',
      '{;list*}' => ';list=red;list=green;list=blue',
      '{;keys}' => ';keys=semi,%3B,dot,.,comma,%2C',
      '{;keys*}' => ';semi=%3B;dot=.;comma=%2C',
    }
  end
  context "form query expansion (?)" do
    it_behaves_like 'expands', {
      '{?who}' => '?who=fred',
      '{?half}' => '?half=50%25',
      '{?x,y}' => '?x=1024&y=768',
      '{?x,y,empty}' => '?x=1024&y=768&empty=',
      '{?x,y,undef}' => '?x=1024&y=768',
      '{?var:3}' => '?var=val',
      '{?list}' => '?list=red,green,blue',
      '{?list*}' => '?list=red&list=green&list=blue',
      '{?keys}' => '?keys=semi,%3B,dot,.,comma,%2C',
      '{?keys*}' => '?semi=%3B&dot=.&comma=%2C',
    }
  end
  context "form query expansion (&)" do
    it_behaves_like 'expands', {
      '{&who}' => '&who=fred',
      '{&half}' => '&half=50%25',
      '?fixed=yes{&x}' => '?fixed=yes&x=1024',
      '{&x,y,empty}' => '&x=1024&y=768&empty=',
      '{&x,y,undef}' => '&x=1024&y=768',
      '{&var:3}' => '&var=val',
      '{&list}' => '&list=red,green,blue',
      '{&list*}' => '&list=red&list=green&list=blue',
      '{&keys}' => '&keys=semi,%3B,dot,.,comma,%2C',
      '{&keys*}' => '&semi=%3B&dot=.&comma=%2C',
    }
  end
  context "non-string key in match data" do
    subject {Addressable::Template.new("http://example.com/{one}")}

    it "raises TypeError" do
      expect { subject.expand(Object.new => "1") }.to raise_error TypeError
    end
  end

  # RFC 6570 section 2.3: a list or associative array with no defined
  # members is undefined, and undefined (nil) members are left out.
  context "undefined list and associative array members" do
    subject {
      {
        "x" => "1",
        "empty_list" => [],
        "empty_keys" => {},
        "nil_list" => [nil],
        "nils" => [nil, nil],
        "mixed" => ["a", nil, "b"],
        "nil_keys" => {"k" => nil},
        "mixed_keys" => {"a" => "1", "b" => nil}
      }
    }
    it_behaves_like 'expands', {
      'X{empty_list}Y' => 'XY',
      'X{#empty_list}Y' => 'XY',
      'X{.empty_list}Y' => 'XY',
      'X{/empty_list*}Y' => 'XY',
      'X{;empty_list}Y' => 'XY',
      'X{;empty_list*}Y' => 'XY',
      'X{?empty_list}Y' => 'XY',
      'X{&empty_list*}Y' => 'XY',
      'X{#empty_keys}Y' => 'XY',
      'X{?empty_keys*}Y' => 'XY',
      'X{nil_list}Y' => 'XY',
      'X{#nils}Y' => 'XY',
      'X{/nils*}Y' => 'XY',
      'X{;nils*}Y' => 'XY',
      'X{?nil_list}Y' => 'XY',
      'X{nil_keys}Y' => 'XY',
      'X{+nil_keys*}Y' => 'XY',
      'X{?nil_keys}Y' => 'XY',
      'X{mixed}Y' => 'Xa,bY',
      'X{.mixed*}Y' => 'X.a.bY',
      'X{/mixed*}Y' => 'X/a/bY',
      'X{;mixed*}Y' => 'X;mixed=a;mixed=bY',
      'X{?mixed*}Y' => 'X?mixed=a&mixed=bY',
      'X{mixed_keys}Y' => 'Xa,1Y',
      'X{;mixed_keys*}Y' => 'X;a=1Y',
      'X{?mixed_keys*}Y' => 'X?a=1Y',
      '{?empty_list,x}' => '?x=1',
      '{?x,nil_list}' => '?x=1',
      '{?mixed_keys*,x}' => '?a=1&x=1',
      '{;nils,x}' => ';x=1',
      '{/nil_keys,x}' => '/1'
    }

    it "doesn't change the values" do
      mapping = subject
      Addressable::Template.new("{mixed}{?mixed_keys*}").expand(mapping)
      expect(mapping["mixed"]).to eq(["a", nil, "b"])
      expect(mapping["mixed_keys"]).to eq({"a" => "1", "b" => nil})
    end

    it "expands a value with nil members as the value without them" do
      rng = Random.new(611)
      names = %w(a b c d)
      values = [
        nil, "", "v", [], [nil], [nil, nil], ["1", nil, "2"], ["1"],
        {}, {"k" => nil}, {"k" => "1", "j" => nil}, {"k" => "1"}
      ]
      operators = ["", "+", "#", ".", "/", ";", "?", "&"]
      wrong = []
      2000.times do
        varlist = names.sample(rng.rand(1..3), random: rng).map do |name|
          rng.rand(4).zero? ? "#{name}*" : name
        end
        template = Addressable::Template.new(
          "x{#{operators.sample(random: rng)}#{varlist.join(",")}}y"
        )
        mapping = {}
        names.each do |name|
          mapping[name] = values.sample(random: rng) if rng.rand(3) > 0
        end
        defined = {}
        mapping.each do |name, value|
          value = if value.kind_of?(Hash)
            value.reject { |_, member| member.nil? }
          elsif value.kind_of?(Array)
            value.compact
          else
            value
          end
          defined[name] = value unless value == [] || value == {}
        end
        expanded = template.expand(mapping).to_s
        if expanded != template.expand(defined).to_s
          wrong << [template.pattern, mapping, expanded]
        end
      end
      expect(wrong.first(5)).to eq([])
    end
  end
end

class ExampleTwoProcessor
  def self.restore(name, value)
    return value.gsub(/-/, " ") if name == "query"
    return value
  end

  def self.match(name)
    return ".*?" if name == "first"
    return ".*"
  end
  def self.validate(name, value)
    return !!(value =~ /^[\w ]+$/) if name == "query"
    return true
  end

  def self.transform(name, value)
    return value.gsub(/ /, "+") if name == "query"
    return value
  end
end

class DumbProcessor
  def self.match(name)
    return ".*?" if name == "first"
  end
end

describe Addressable::Template do
  describe 'initialize' do
    context 'with a non-string' do
      it 'raises a TypeError' do
        expect { Addressable::Template.new(nil) }.to raise_error(TypeError)
      end
    end
  end

  describe 'freeze' do
    subject { Addressable::Template.new("http://example.com/{first}/{+second}/") }
    it 'freezes the template' do
      expect(subject.freeze).to be_frozen
    end
  end

  describe "Matching" do
    let(:uri){
      Addressable::URI.parse(
        "http://example.com/search/an-example-search-query/"
      )
    }
    let(:uri2){
      Addressable::URI.parse("http://example.com/a/b/c/")
    }
    let(:uri3){
      Addressable::URI.parse("http://example.com/;a=1;b=2;c=3;first=foo")
    }
    let(:uri4){
      Addressable::URI.parse("http://example.com/?a=1&b=2&c=3&first=foo")
    }
    let(:uri5){
      "http://example.com/foo"
    }
    context "first uri with ExampleTwoProcessor" do
      subject {
        Addressable::Template.new(
          "http://example.com/search/{query}/"
        ).match(uri, ExampleTwoProcessor)
      }
      its(:variables){ should == ["query"] }
      its(:captures){ should == ["an example search query"] }
    end

    context "second uri with ExampleTwoProcessor" do
      subject {
        Addressable::Template.new(
          "http://example.com/{first}/{+second}/"
        ).match(uri2, ExampleTwoProcessor)
      }
      its(:variables){ should == ["first", "second"] }
      its(:captures){ should == ["a", "b/c"] }
    end

    context "second uri with DumbProcessor" do
      subject {
        Addressable::Template.new(
          "http://example.com/{first}/{+second}/"
        ).match(uri2, DumbProcessor)
      }
      its(:variables){ should == ["first", "second"] }
      its(:captures){ should == ["a", "b/c"] }
    end

    context "second uri" do
      subject {
        Addressable::Template.new(
          "http://example.com/{first}{/second*}/"
        ).match(uri2)
      }
      its(:variables){ should == ["first", "second"] }
      its(:captures){ should == ["a", ["b","c"]] }
    end
    context "third uri" do
      subject {
        Addressable::Template.new(
          "http://example.com/{;hash*,first}"
        ).match(uri3)
      }
      its(:variables){ should == ["hash", "first"] }
      its(:captures){ should == [
        {"a" => "1", "b" => "2", "c" => "3", "first" => "foo"}, nil] }
    end
    # Note that this expansion is impossible to revert deterministically - the
    # * operator means first could have been a key of hash or a separate key.
    # Semantically, a separate key is more likely, but both are possible.
    context "fourth uri" do
      subject {
        Addressable::Template.new(
          "http://example.com/{?hash*,first}"
        ).match(uri4)
      }
      its(:variables){ should == ["hash", "first"] }
      its(:captures){ should == [
        {"a" => "1", "b" => "2", "c" => "3", "first"=> "foo"}, nil] }
    end
    context "fifth uri" do
      subject {
        Addressable::Template.new(
          "http://example.com/{path}{?hash*,first}"
        ).match(uri5)
      }
      its(:variables){ should == ["path", "hash", "first"] }
      its(:captures){ should == ["foo", nil, nil] }
    end
    context "multi-variable + expression followed by a literal" do
      subject {
        Addressable::Template.new(
          "http://example.com/{+base,file}/edit"
        ).match("http://example.com/docs/readme/edit")
      }
      its(:variables){ should == ["base", "file"] }
      its(:captures){ should == [nil, "docs/readme"] }
    end
    context "multi-variable # expression followed by a literal" do
      subject {
        Addressable::Template.new(
          "http://example.com/{#a,b}/{+c}"
        ).match("http://example.com/#x/")
      }
      its(:variables){ should == ["a", "b", "c"] }
      its(:captures){ should == [nil, "x", nil] }
    end
    context "+ expression with a variable before an explode modifier" do
      subject {
        Addressable::Template.new(
          "http://example.com/{+path,segments*}"
        ).match("http://example.com/a/b")
      }
      its(:variables){ should == ["path", "segments"] }
      its(:captures){ should == ["a/b", []] }
    end
  end

  describe 'match' do
    subject { Addressable::Template.new('http://example.com/first/second/') }
    context 'when the URI is the same as the template' do
      it 'returns the match data itself with an empty mapping' do
        uri = Addressable::URI.parse('http://example.com/first/second/')
        match_data = subject.match(uri)
        expect(match_data).to be_an Addressable::Template::MatchData
        expect(match_data.uri).to eq(uri)
        expect(match_data.template).to eq(subject)
        expect(match_data.mapping).to be_empty
        expect(match_data.inspect).to be_an String
      end
    end
  end

  describe "extract" do
    let(:template) {
      Addressable::Template.new(
        "http://{host}{/segments*}/{?one,two,bogus}{#fragment}"
      )
    }
    let(:uri){ "http://example.com/a/b/c/?one=1&two=2#foo" }
    let(:uri2){ "http://example.com/a/b/c/#foo" }
    it "should be able to extract with queries" do
      expect(template.extract(uri)).to eq({
        "host" => "example.com",
        "segments" => %w(a b c),
        "one" => "1",
        "bogus" => nil,
        "two" => "2",
        "fragment" => "foo"
      })
    end
    it "should be able to extract without queries" do
      expect(template.extract(uri2)).to eq({
        "host" => "example.com",
        "segments" => %w(a b c),
        "one" => nil,
        "bogus" => nil,
        "two" => nil,
        "fragment" => "foo"
      })
    end

    context "issue #137" do
      subject { Addressable::Template.new('/path{?page,per_page}') }

      it "can match empty" do
        data = subject.extract("/path")
        expect(data["page"]).to eq(nil)
        expect(data["per_page"]).to eq(nil)
        expect(data.keys.sort).to eq(['page', 'per_page'])
      end

      it "can match first var" do
        data = subject.extract("/path?page=1")
        expect(data["page"]).to eq("1")
        expect(data["per_page"]).to eq(nil)
        expect(data.keys.sort).to eq(['page', 'per_page'])
      end

      it "can match second var" do
        data = subject.extract("/path?per_page=1")
        expect(data["page"]).to eq(nil)
        expect(data["per_page"]).to eq("1")
        expect(data.keys.sort).to eq(['page', 'per_page'])
      end

      it "can match both vars" do
        data = subject.extract("/path?page=2&per_page=1")
        expect(data["page"]).to eq("2")
        expect(data["per_page"]).to eq("1")
        expect(data.keys.sort).to eq(['page', 'per_page'])
      end
    end
  end

  describe "Partial expand with symbols" do
    context "partial_expand with two simple values" do
      subject {
        Addressable::Template.new("http://example.com/{one}/{two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand(:one => "1").pattern).to eq(
          "http://example.com/1/{two}/"
        )
      end
    end
    context "partial_expand query with missing param in middle" do
      subject {
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand(:one => "1", :three => "3").pattern).to eq(
          "http://example.com/?one=1{&two}&three=3/"
        )
      end
    end
    context "partial_expand form style query with missing param at beginning" do
      subject {
        Addressable::Template.new("http://example.com/{?one,two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand(:two => "2").pattern).to eq(
          "http://example.com/?two=2{&one}/"
        )
      end
    end
    context "issue #307 - partial_expand form query with nil params" do
      subject do
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      end
      it "builds a new pattern with two=nil" do
        expect(subject.partial_expand(two: nil).pattern).to eq(
          "http://example.com/{?one}{&three}/"
        )
      end
      it "builds a new pattern with one=nil and two=nil" do
        expect(subject.partial_expand(one: nil, two: nil).pattern).to eq(
          "http://example.com/{?three}/"
        )
      end
      it "builds a new pattern with one=1 and two=nil" do
        expect(subject.partial_expand(one: 1, two: nil).pattern).to eq(
          "http://example.com/?one=1{&three}/"
        )
      end
      it "builds a new pattern with one=nil and two=2" do
        expect(subject.partial_expand(one: nil, two: 2).pattern).to eq(
          "http://example.com/?two=2{&three}/"
        )
      end
      it "builds a new pattern with one=nil" do
        expect(subject.partial_expand(one: nil).pattern).to eq(
          "http://example.com/{?two}{&three}/"
        )
      end
    end
    context "partial_expand with query string" do
      subject {
        Addressable::Template.new("http://example.com/{?two,one}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand(:one => "1").pattern).to eq(
          "http://example.com/?one=1{&two}/"
        )
      end
    end
    context "partial_expand with path operator" do
      subject {
        Addressable::Template.new("http://example.com{/one,two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand(:one => "1").pattern).to eq(
          "http://example.com/1{/two}/"
        )
      end
    end
    context "partial expand with unicode values" do
      subject do
        Addressable::Template.new("http://example.com/{resource}/{query}/")
      end
      it "normalizes unicode by default" do
        template = subject.partial_expand("query" => "Cafe\u0301")
        expect(template.pattern).to eq(
          "http://example.com/{resource}/Caf%C3%A9/"
        )
      end

      it "normalizes as unicode even with wrong encoding specified" do
        template = subject.partial_expand("query" => "Cafe\u0301".b)
        expect(template.pattern).to eq(
          "http://example.com/{resource}/Caf%C3%A9/"
        )
      end

      it "raises on invalid unicode input" do
        expect {
          subject.partial_expand("query" => "M\xE9thode".b)
        }.to raise_error(ArgumentError, "invalid byte sequence in UTF-8")
      end

      it "does not normalize unicode when byte semantics requested" do
        template = subject.partial_expand({"query" => "Cafe\u0301"}, nil, false)
        expect(template.pattern).to eq(
          "http://example.com/{resource}/Cafe%CC%81/"
        )
      end
    end
  end
  describe "Partial expand with undefined members" do
    subject {
      Addressable::Template.new("http://example.com/{?empty,y,x}")
    }
    it "skips an empty list when choosing the first query variable" do
      expect(subject.partial_expand("empty" => [], "x" => "1").pattern).to eq(
        "http://example.com/?x=1{&y}"
      )
    end
    it "skips an empty associative array" do
      expect(subject.partial_expand("empty" => {}, "x" => "1").pattern).to eq(
        "http://example.com/?x=1{&y}"
      )
    end
    it "skips a list with only nil members" do
      expect(
        subject.partial_expand("empty" => [nil, nil], "x" => "1").pattern
      ).to eq("http://example.com/?x=1{&y}")
    end
    it "skips an associative array with only nil members" do
      expect(
        subject.partial_expand("empty" => {"k" => nil}, "x" => "1").pattern
      ).to eq("http://example.com/?x=1{&y}")
    end
    it "keeps the query valid when the rest is undefined" do
      partial = subject.partial_expand("empty" => [nil], "x" => "1")
      expect(partial.expand({}).to_s).to eq("http://example.com/?x=1")
      expect(partial.expand("y" => "2").to_s).to eq(
        "http://example.com/?x=1&y=2"
      )
    end
    it "treats a list with only nil members as nil" do
      expect(subject.partial_expand("empty" => [nil]).pattern).to eq(
        subject.partial_expand("empty" => nil).pattern
      )
    end

    it "expands to the same URI as a full expansion" do
      rng = Random.new(6110)
      names = %w(a b c d)
      values = [
        nil, "", "v", [], [nil], [nil, nil], ["1", nil, "2"], ["1"],
        {}, {"k" => nil}, {"k" => "1", "j" => nil}, {"k" => "1"}
      ]
      wrong = []
      2000.times do
        operator = [".", "/", ";", "?", "&"].sample(random: rng)
        varlist = names.sample(rng.rand(1..3), random: rng).map do |name|
          rng.rand(4).zero? ? "#{name}*" : name
        end
        template = Addressable::Template.new(
          "x{#{operator}#{varlist.join(",")}}y"
        )
        mapping = {}
        names.each do |name|
          mapping[name] = values.sample(random: rng) if rng.rand(3) > 0
        end
        partial = template.partial_expand(mapping).expand({}).to_s
        full = template.expand(mapping).to_s
        if partial != full
          wrong << [template.pattern, mapping, partial, full]
        end
      end
      expect(wrong.first(5)).to eq([])
    end
  end

  describe "Partial expand with strings" do
    context "partial_expand with two simple values" do
      subject {
        Addressable::Template.new("http://example.com/{one}/{two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1").pattern).to eq(
          "http://example.com/1/{two}/"
        )
      end
    end
    context "partial_expand query with missing param in middle" do
      subject {
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1", "three" => "3").pattern).to eq(
          "http://example.com/?one=1{&two}&three=3/"
        )
      end
    end
    context "partial_expand with query string" do
      subject {
        Addressable::Template.new("http://example.com/{?two,one}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1").pattern).to eq(
          "http://example.com/?one=1{&two}/"
        )
      end
    end
    context "partial_expand with path operator" do
      subject {
        Addressable::Template.new("http://example.com{/one,two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1").pattern).to eq(
          "http://example.com/1{/two}/"
        )
      end
    end
  end
  describe "Expand" do
    context "expand with unicode values" do
      subject do
        Addressable::Template.new("http://example.com/search/{query}/")
      end
      it "normalizes unicode by default" do
        uri = subject.expand("query" => "Cafe\u0301").to_str
        expect(uri).to eq("http://example.com/search/Caf%C3%A9/")
      end

      it "normalizes as unicode even with wrong encoding specified" do
        uri = subject.expand("query" => "Cafe\u0301".b).to_str
        expect(uri).to eq("http://example.com/search/Caf%C3%A9/")
      end

      it "raises on invalid unicode input" do
        expect {
          subject.expand("query" => "M\xE9thode".b).to_str
        }.to raise_error(ArgumentError, "invalid byte sequence in UTF-8")
      end

      it "does not normalize unicode when byte semantics requested" do
        uri = subject.expand({ "query" => "Cafe\u0301" }, nil, false).to_str
        expect(uri).to eq("http://example.com/search/Cafe%CC%81/")
      end
    end
    context "expand with array values" do
      subject { Addressable::Template.new("http://example.com/{?list*}") }
      let(:list) { ["Cafe\u0301", 1, :two] }

      it "leaves the array unchanged" do
        uri = subject.expand("list" => list).to_str
        expect(uri).to eq("http://example.com/?list=Caf%C3%A9&list=1&list=two")
        expect(list).to eq(["Cafe\u0301", 1, :two])
      end

      it "leaves the array unchanged in a partial expansion" do
        template = Addressable::Template.new("http://example.com/{?list*,x}")
        expect(template.partial_expand("list" => list).pattern).to eq(
          "http://example.com/?list=Caf%C3%A9&list=1&list=two{&x}"
        )
        expect(list).to eq(["Cafe\u0301", 1, :two])
      end

      it "expands a frozen array" do
        uri = subject.expand("list" => ["Cafe\u0301", "b"].freeze).to_str
        expect(uri).to eq("http://example.com/?list=Caf%C3%A9&list=b")
      end

      it "expands a frozen array in a partial expansion" do
        template = Addressable::Template.new("http://example.com/{?list*,x}")
        expect(template.partial_expand("list" => %w(a b).freeze).pattern).to eq(
          "http://example.com/?list=a&list=b{&x}"
        )
      end

      it "expands an object that converts to an array" do
        list = Struct.new(:to_ary).new(["Cafe\u0301", 2].freeze)
        uri = subject.expand("list" => list).to_str
        expect(uri).to eq("http://example.com/?list=Caf%C3%A9&list=2")
        expect(list.to_ary).to eq(["Cafe\u0301", 2])
      end

      it "leaves an array returned by a processor unchanged" do
        result = ["Cafe\u0301", "b"]
        processor = Object.new
        processor.define_singleton_method(:transform) { |_name, _value| result }
        template = Addressable::Template.new("http://example.com{/list*}")
        expect(template.expand({ "list" => "x" }, processor).to_str).to eq(
          "http://example.com/Caf\u00e9/b"
        )
        expect(result).to eq(["Cafe\u0301", "b"])
      end

      it "expands a frozen array returned by a processor" do
        processor = Object.new
        processor.define_singleton_method(:transform) do |_name, _value|
          %w(a b).freeze
        end
        template = Addressable::Template.new("http://example.com{/list*}")
        expect(template.expand({ "list" => "x" }, processor).to_str).to eq(
          "http://example.com/a/b"
        )
      end
    end
    context "expand with a processor" do
      subject {
        Addressable::Template.new("http://example.com/search/{query}/")
      }
      it "processes spaces" do
        expect(subject.expand({"query" => "an example search query"},
                      ExampleTwoProcessor).to_str).to eq(
          "http://example.com/search/an+example+search+query/"
        )
      end
      it "validates" do
        expect{
          subject.expand({"query" => "Bogus!"},
                      ExampleTwoProcessor).to_str
        }.to raise_error(Addressable::Template::InvalidTemplateValueError)
      end
    end
    context "partial_expand query with missing param in middle" do
      subject {
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1", "three" => "3").pattern).to eq(
          "http://example.com/?one=1{&two}&three=3/"
        )
      end
    end
    context "partial_expand with query string" do
      subject {
        Addressable::Template.new("http://example.com/{?two,one}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1").pattern).to eq(
          "http://example.com/?one=1{&two}/"
        )
      end
    end
    context "partial_expand with path operator" do
      subject {
        Addressable::Template.new("http://example.com{/one,two}/")
      }
      it "builds a new pattern" do
        expect(subject.partial_expand("one" => "1").pattern).to eq(
          "http://example.com/1{/two}/"
        )
      end
    end
  end
  context "Matching with operators" do
    describe "Level 1:" do
      subject { Addressable::Template.new("foo{foo}/{bar}baz") }
      it "can match" do
        data = subject.match("foofoo/bananabaz")
        expect(data.mapping["foo"]).to eq("foo")
        expect(data.mapping["bar"]).to eq("banana")
      end
      it "can fail" do
        expect(subject.match("bar/foo")).to be_nil
        expect(subject.match("foobaz")).to be_nil
      end
      it "can match empty" do
        data = subject.match("foo/baz")
        expect(data.mapping["foo"]).to eq(nil)
        expect(data.mapping["bar"]).to eq(nil)
      end
      it "lists vars" do
        expect(subject.variables).to eq(["foo", "bar"])
      end
    end

    describe "Level 2:" do
      subject { Addressable::Template.new("foo{+foo}{#bar}baz") }
      it "can match" do
        data = subject.match("foo/test/banana#bazbaz")
        expect(data.mapping["foo"]).to eq("/test/banana")
        expect(data.mapping["bar"]).to eq("baz")
      end
      it "can match empty level 2 #" do
        data = subject.match("foo/test/bananabaz")
        expect(data.mapping["foo"]).to eq("/test/banana")
        expect(data.mapping["bar"]).to eq(nil)
        data = subject.match("foo/test/banana#baz")
        expect(data.mapping["foo"]).to eq("/test/banana")
        expect(data.mapping["bar"]).to eq("")
      end
      it "can match empty level 2 +" do
        data = subject.match("foobaz")
        expect(data.mapping["foo"]).to eq(nil)
        expect(data.mapping["bar"]).to eq(nil)
        data = subject.match("foo#barbaz")
        expect(data.mapping["foo"]).to eq(nil)
        expect(data.mapping["bar"]).to eq("bar")
      end
      it "lists vars" do
        expect(subject.variables).to eq(["foo", "bar"])
      end
    end

    describe "Level 3:" do
      context "no operator" do
        subject { Addressable::Template.new("foo{foo,bar}baz") }
        it "can match" do
          data = subject.match("foofoo,barbaz")
          expect(data.mapping["foo"]).to eq("foo")
          expect(data.mapping["bar"]).to eq("bar")
        end
        it "lists vars" do
          expect(subject.variables).to eq(["foo", "bar"])
        end
      end
      context "+ operator" do
        subject { Addressable::Template.new("{+foo,bar}") }
        it "can match" do
          data = subject.match("foo/bar,baz")
          expect(data.mapping["foo"]).to eq("foo/bar")
          expect(data.mapping["bar"]).to eq("baz")
        end
        it "lists vars" do
          expect(subject.variables).to eq(["foo", "bar"])
        end
      end
      context "+ operator with explode modifier" do
        subject { Addressable::Template.new("{+foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a," * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "# operator with explode modifier" do
        subject { Addressable::Template.new("{#foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("#" + "a," * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "+ operator with explode modifier and surrounding literals" do
        subject { Addressable::Template.new("x{+foo*}y") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match("x" + ("a," * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "+ operator with multiple explode-modified variables" do
        subject { Addressable::Template.new("{+foo*,bar*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a," * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "default operator with explode modifier" do
        subject { Addressable::Template.new("{foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a," * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "/ operator with explode modifier" do
        subject { Addressable::Template.new("{/foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a/" * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context ". operator with explode modifier" do
        subject { Addressable::Template.new("{.foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a." * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "; operator with explode modifier" do
        subject { Addressable::Template.new("{;foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a=1;" * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      {
        "{/foo*}" => "/" + ("a/" * 1000) + "!",
        "/prefix{/foo*}" => "/prefix/" + ("a/" * 1000) + "!",
        "{.foo*}" => "." + ("a." * 1000) + "!",
        "{;foo*}" => ";" + ("a=1;" * 1000) + "!",
        "{;foo*} (members without values)" => ";" + ("ab;" * 1000) + "!"
      }.each do |pattern, payload|
        context "#{pattern} against a payload starting with its operator" do
          subject { Addressable::Template.new(pattern.split(" ").first) }
          it "should match in linear time against a non-matching payload" do
            expect do
              Timeout.timeout(10) do
                expect(subject.match(payload)).to be_nil
              end
            end.not_to raise_error
          end
        end
      end
      context "? operator with explode modifier" do
        subject { Addressable::Template.new("{?foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match("?" + ("a=1&" * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "& operator with explode modifier" do
        subject { Addressable::Template.new("{&foo*}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("&a=1" * 1000) + "!")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "many variables in a single + expression" do
        subject { Addressable::Template.new("{+v1,v2,v3,v4,v5,v6,v7,v8,v9,v10}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a," * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "consecutive + expressions without separators" do
        subject { Addressable::Template.new("{+a}{+b}{+c}") }
        it "should match in linear time against a non-matching payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("a" * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context "percent-encoded payload with + explode modifier" do
        subject { Addressable::Template.new("{+foo*}") }
        it "should match in linear time against a non-matching percent-encoded payload" do
          expect do
            Timeout.timeout(10) do
              expect(subject.match(("%2F" * 1000) + " ")).to be_nil
            end
          end.not_to raise_error
        end
      end
      context ". operator" do
        subject { Addressable::Template.new("foo{.foo,bar}baz") }
        it "can match" do
          data = subject.match("foo.foo.barbaz")
          expect(data.mapping["foo"]).to eq("foo")
          expect(data.mapping["bar"]).to eq("bar")
        end
        it "lists vars" do
          expect(subject.variables).to eq(["foo", "bar"])
        end
      end
      context "/ operator" do
        subject { Addressable::Template.new("foo{/foo,bar}baz") }
        it "can match" do
          data = subject.match("foo/foo/barbaz")
          expect(data.mapping["foo"]).to eq("foo")
          expect(data.mapping["bar"]).to eq("bar")
        end
        it "lists vars" do
          expect(subject.variables).to eq(["foo", "bar"])
        end
      end
      context "; operator" do
        subject { Addressable::Template.new("foo{;foo,bar,baz}baz") }
        it "can match" do
          data = subject.match("foo;foo=bar%20baz;bar=foo;bazbaz")
          expect(data.mapping["foo"]).to eq("bar baz")
          expect(data.mapping["bar"]).to eq("foo")
          expect(data.mapping["baz"]).to eq("")
        end
        it "lists vars" do
          expect(subject.variables).to eq(%w(foo bar baz))
        end
      end
      context "? operator" do
        context "test" do
          subject { Addressable::Template.new("foo{?foo,bar}baz") }
          it "can match" do
            data = subject.match("foo?foo=bar%20baz&bar=foobaz")
            expect(data.mapping["foo"]).to eq("bar baz")
            expect(data.mapping["bar"]).to eq("foo")
          end
          it "lists vars" do
            expect(subject.variables).to eq(%w(foo bar))
          end
        end

        context "issue #137" do
          subject { Addressable::Template.new('/path{?page,per_page}') }

          it "can match empty" do
            data = subject.match("/path")
            expect(data.mapping["page"]).to eq(nil)
            expect(data.mapping["per_page"]).to eq(nil)
            expect(data.mapping.keys.sort).to eq(['page', 'per_page'])
          end

          it "can match first var" do
            data = subject.match("/path?page=1")
            expect(data.mapping["page"]).to eq("1")
            expect(data.mapping["per_page"]).to eq(nil)
            expect(data.mapping.keys.sort).to eq(['page', 'per_page'])
          end

          it "can match second var" do
            data = subject.match("/path?per_page=1")
            expect(data.mapping["page"]).to eq(nil)
            expect(data.mapping["per_page"]).to eq("1")
            expect(data.mapping.keys.sort).to eq(['page', 'per_page'])
          end

          it "can match both vars" do
            data = subject.match("/path?page=2&per_page=1")
            expect(data.mapping["page"]).to eq("2")
            expect(data.mapping["per_page"]).to eq("1")
            expect(data.mapping.keys.sort).to eq(['page', 'per_page'])
          end
        end

        context "issue #71" do
          subject { Addressable::Template.new("http://cyberscore.dev/api/users{?username}") }
          it "can match" do
            data = subject.match("http://cyberscore.dev/api/users?username=foobaz")
            expect(data.mapping["username"]).to eq("foobaz")
          end
          it "lists vars" do
            expect(subject.variables).to eq(%w(username))
            expect(subject.keys).to eq(%w(username))
          end
        end
      end
      context "& operator" do
        subject { Addressable::Template.new("foo{&foo,bar}baz") }
        it "can match" do
          data = subject.match("foo&foo=bar%20baz&bar=foobaz")
          expect(data.mapping["foo"]).to eq("bar baz")
          expect(data.mapping["bar"]).to eq("foo")
        end
        it "lists vars" do
          expect(subject.variables).to eq(%w(foo bar))
        end
      end
    end
  end

  context "support regexes:" do
    context "EXPRESSION" do
      subject { Addressable::Template::EXPRESSION }
      it "should be able to match an expression" do
        expect(subject).to match("{foo}")
        expect(subject).to match("{foo,9}")
        expect(subject).to match("{foo.bar,baz}")
        expect(subject).to match("{+foo.bar,baz}")
        expect(subject).to match("{foo,foo%20bar}")
        expect(subject).to match("{#foo:20,baz*}")
        expect(subject).to match("stuff{#foo:20,baz*}things")
      end
      it "should fail on non vars" do
        expect(subject).not_to match("!{foo")
        expect(subject).not_to match("{foo.bar.}")
        expect(subject).not_to match("!{}")
      end
    end
    context "VARNAME" do
      subject { Addressable::Template::VARNAME }
      it "should be able to match a variable" do
        expect(subject).to match("foo")
        expect(subject).to match("9")
        expect(subject).to match("foo.bar")
        expect(subject).to match("foo_bar")
        expect(subject).to match("foo_bar.baz")
        expect(subject).to match("foo%20bar")
        expect(subject).to match("foo%20bar.baz")
      end
      it "should fail on non vars" do
        expect(subject).not_to match("!foo")
        expect(subject).not_to match("foo.bar.")
        expect(subject).not_to match("foo%2%00bar")
        expect(subject).not_to match("foo_ba%r")
        expect(subject).not_to match("foo_bar*")
        expect(subject).not_to match("foo_bar:20")
      end

      it 'should parse in a reasonable time' do
        expect do
          Timeout.timeout(0.1) do
            expect(subject).not_to match("0"*25 + "!")
          end
        end.not_to raise_error
      end
    end
    context "VARIABLE_LIST" do
      subject { Addressable::Template::VARIABLE_LIST }
      it "should be able to match a variable list" do
        expect(subject).to match("foo,bar")
        expect(subject).to match("foo")
        expect(subject).to match("foo,bar*,baz")
        expect(subject).to match("foo.bar,bar_baz*,baz:12")
      end
      it "should fail on non vars" do
        expect(subject).not_to match(",foo,bar*,baz")
        expect(subject).not_to match("foo,*bar,baz")
        expect(subject).not_to match("foo,,bar*,baz")
      end
    end
    context "VARSPEC" do
      subject { Addressable::Template::VARSPEC }
      it "should be able to match a variable with modifier" do
        expect(subject).to match("9:8")
        expect(subject).to match("foo.bar*")
        expect(subject).to match("foo_bar:12")
        expect(subject).to match("foo_bar.baz*")
        expect(subject).to match("foo%20bar:12")
        expect(subject).to match("foo%20bar.baz*")
      end
      it "should fail on non vars" do
        expect(subject).not_to match("!foo")
        expect(subject).not_to match("*foo")
        expect(subject).not_to match("fo*o")
        expect(subject).not_to match("fo:o")
        expect(subject).not_to match("foo:")
      end
    end
  end
end

describe Addressable::Template::MatchData do
  let(:template) { Addressable::Template.new('{foo}/{bar}') }
  subject(:its) { template.match('ab/cd') }
  its(:uri) { should == Addressable::URI.parse('ab/cd') }
  its(:template) { should == template }
  its(:mapping) { should == { 'foo' => 'ab', 'bar' => 'cd' } }
  its(:variables) { should == ['foo', 'bar'] }
  its(:keys) { should == ['foo', 'bar'] }
  its(:names) { should == ['foo', 'bar'] }
  its(:values) { should == ['ab', 'cd'] }
  its(:captures) { should == ['ab', 'cd'] }
  its(:to_a) { should == ['ab/cd', 'ab', 'cd'] }
  its(:to_s) { should == 'ab/cd' }
  its(:string) { should == its.to_s }
  its(:pre_match) { should == "" }
  its(:post_match) { should == "" }

  describe 'values_at' do
    it 'returns an array with the values' do
      expect(its.values_at(0, 2)).to eq(['ab/cd', 'cd'])
    end
    it 'allows mixing integer an string keys' do
      expect(its.values_at('foo', 1)).to eq(['ab', 'ab'])
    end
    it 'accepts unknown keys' do
      expect(its.values_at('baz', 'foo')).to eq([nil, 'ab'])
    end
  end

  describe '[]' do
    context 'string key' do
      it 'returns the corresponding capture' do
        expect(its['foo']).to eq('ab')
        expect(its['bar']).to eq('cd')
      end
      it 'returns nil for unknown keys' do
        expect(its['baz']).to be_nil
      end
    end
    context 'symbol key' do
      it 'returns the corresponding capture' do
        expect(its[:foo]).to eq('ab')
        expect(its[:bar]).to eq('cd')
      end
      it 'returns nil for unknown keys' do
        expect(its[:baz]).to be_nil
      end
    end
    context 'integer key' do
      it 'returns the full URI for index 0' do
        expect(its[0]).to eq('ab/cd')
      end
      it 'returns the corresponding capture' do
        expect(its[1]).to eq('ab')
        expect(its[2]).to eq('cd')
      end
      it 'returns nil for unknown keys' do
        expect(its[3]).to be_nil
      end
    end
    context 'other key' do
      it 'raises an exception' do
        expect { its[Object.new] }.to raise_error(TypeError)
      end
    end
    context 'with length' do
      it 'returns an array starting at index with given length' do
        expect(its[0, 2]).to eq(['ab/cd', 'ab'])
        expect(its[2, 1]).to eq(['cd'])
      end
    end
  end
end
