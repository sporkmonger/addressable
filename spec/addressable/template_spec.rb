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

    it "#{template} to #{exp} from a lambda" do
      mapping = subject
      lookup = lambda do |name|
        mapping.key?(name) ? mapping[name] : mapping[name.to_sym]
      end
      tmpl = Addressable::Template.new(template).expand(lookup)
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

describe Addressable::Template, "when partially expanded" do
  def self.cases(count, seed)
    random = Random.new(seed)
    operators = ["", "+", "#", ".", "/", ";", "?", "&"]
    values = [
      "1", "x y", "", nil, ["a", "b"], [], {"k" => "v"},
      {"k" => "v", "j" => "w"}
    ]
    Array.new(count) do
      operator = operators[random.rand(operators.size)]
      vars = ["a", "b", "c"].shuffle(random: random).first(random.rand(1..3))
      varspecs = vars.map { |name| random.rand(4) == 0 ? "#{name}*" : name }
      given = vars.select { random.rand(2) == 0 }
      first = Hash[given.map do |name|
        [name, values[random.rand(values.size)]]
      end]
      later = Hash[(vars - given).map do |name|
        [name, values[random.rand(values.size)]]
      end]
      ["{#{operator}#{varspecs.join(",")}}", first, later]
    end
  end

  def self.query_pairs(string)
    leader = string[0, 1]
    pairs = string.sub(/\A[?&]/, "").split("&").sort
    [["?", "&"].include?(leader) ? leader : "", pairs]
  end

  it "gives the same result as expanding at once" do
    failures = []
    self.class.cases(3000, 6570).each do |pattern, first, later|
      template = Addressable::Template.new(pattern)
      direct = template.expand(first.merge(later)).to_str
      staged = template.partial_expand(first).expand(later).to_str
      operator = pattern[1, 1]
      defined_later = later.values.any? do |value|
        !value.nil? && value != [] && value != {}
      end
      exact = if ["?", "&"].include?(operator)
        self.class.query_pairs(staged) == self.class.query_pairs(direct)
      elsif operator =~ /[a-z+#]/ && !first.empty? && defined_later
        # A comma expression can't keep the "," before a variable that's
        # only defined later, so this case is exact only without one.
        true
      else
        staged == direct
      end
      failures << [pattern, first, later, staged, direct] unless exact
    end
    expect(failures).to be_empty, lambda {
      "#{failures.size} partial expansions differ (pattern, first, later, " +
      "staged, direct):\n" +
      failures.first(10).map { |failure| "  #{failure.inspect}" }.join("\n")
    }
  end
end

describe Addressable::Template, "with a mapping that isn't a Hash" do
  it "expands from a lambda" do
    sub = lambda { |name| "foo-#{name}" }
    expect(
      Addressable::Template.new("{bar}/{baz}").expand(sub).to_str
    ).to eq("foo-bar/foo-baz")
  end

  it "expands from a block" do
    result = Addressable::Template.new("{bar}/{baz}").expand do |name|
      "foo-#{name}"
    end
    expect(result.to_str).to eq("foo-bar/foo-baz")
  end

  it "expands from a block with a processor" do
    processor = Object.new
    def processor.transform(name, value)
      value.upcase
    end
    result = Addressable::Template.new("{bar}").expand(nil, processor) do |n|
      "foo-#{n}"
    end
    expect(result.to_str).to eq("FOO-BAR")
  end

  it "expands from any object that responds to []" do
    lookup = Object.new
    def lookup.[](name)
      {"a" => "1", "list" => ["x", "y"], "keys" => {"k" => "v"}}[name]
    end
    expect(
      Addressable::Template.new("{a}{/list*}{?keys*,missing}").expand(
        lookup
      ).to_str
    ).to eq("1/x/y?k=v")
  end

  it "looks up each variable only once" do
    calls = Hash.new(0)
    sub = lambda { |name| calls[name] += 1; "v" }
    Addressable::Template.new("{a}{a}{+a}{?a,b}").expand(sub)
    Addressable::Template.new("{c}{?c,d}").partial_expand(sub)
    expect(calls).to eq("a" => 1, "b" => 1, "c" => 1, "d" => 1)
  end

  it "looks up variables by their names as strings" do
    names = []
    Addressable::Template.new("{a}{x.y}").expand(lambda { |n| names << n; nil })
    expect(names).to eq(["a", "x.y"])
  end

  it "keeps expressions whose variables a lambda raises KeyError for " +
      "when partially expanding" do
    values = {"one" => "1"}
    sub = lambda { |name| values.fetch(name) }
    expect(
      Addressable::Template.new("{one}/{two}").partial_expand(sub).pattern
    ).to eq("1/{two}")
    expect(
      Addressable::Template.new("{one}/{two}").partial_expand do |name|
        {"two" => "2"}.fetch(name)
      end.pattern
    ).to eq("{one}/2")
  end

  it "removes expressions whose variables a block gives nil for when " +
      "partially expanding, as for a Hash value of nil" do
    template = Addressable::Template.new("{one}/{two}{?three}")
    result = template.partial_expand do |name|
      {"one" => "1", "two" => nil}.fetch(name)
    end
    expect(result.pattern).to eq("1/{?three}")
    expect(result).to eq(template.partial_expand("one" => "1", "two" => nil))
  end

  it "treats a KeyError as an undefined variable when expanding" do
    expect(
      Addressable::Template.new("{one}/{two}").expand do |name|
        {"one" => "1"}.fetch(name)
      end.to_str
    ).to eq("1/")
  end

  it "takes a KeyError for a symbol with the variable's name as missing" do
    values = {:one => "1"}
    expect(
      Addressable::Template.new("{one}/{two}").partial_expand do |name|
        values.fetch(name.to_sym)
      end.pattern
    ).to eq("1/{two}")
  end

  it "takes a KeyError with no key as missing" do
    expect(
      Addressable::Template.new("{one}").partial_expand do |name|
        raise KeyError, "no #{name}"
      end.pattern
    ).to eq("{one}")
  end

  if KeyError.method_defined?(:key)
    it "raises a KeyError for a different key" do
      settings = {}
      expect do
        Addressable::Template.new("{one}").partial_expand do |name|
          settings.fetch("other")
        end
      end.to raise_error(KeyError)
    end
  end

  [
    ["{a}/{b}", {"a" => "1"}],
    ["{?a,b,c}", {"b" => "2"}],
    ["{?a,b,c}", {"a" => "1", "c" => 3}],
    ["{&a,b}{/list*}", {"list" => ["x", "y"]}],
    ["{#keys*}{.a}", {"keys" => {"k" => "v"}, "a" => "z"}],
    ["{+a}{;b}", {"a" => "/x", "b" => ""}],
    ["{a}/{b}{?c,d}", {"a" => nil, "c" => nil, "d" => "4"}],
    ["{?a,b,c}", {"a" => nil}]
  ].each do |pattern, hash|
    it "expands '#{pattern}' from a lambda as it would from " +
        "#{hash.inspect}" do
      template = Addressable::Template.new(pattern)
      sub = lambda { |name| hash.fetch(name) }
      expect(template.expand(sub)).to eq(template.expand(hash))
      expect(template.partial_expand(sub)).to eq(template.partial_expand(hash))
    end
  end

  it "uses key? to tell an undefined variable from a missing one when " +
      "partially expanding" do
    lookup = Object.new
    def lookup.[](name)
      {"one" => "1"}[name]
    end
    def lookup.key?(name)
      ["one", "two"].include?(name)
    end
    expect(
      Addressable::Template.new("{one}/{two}/{three}").partial_expand(
        lookup
      ).pattern
    ).to eq("1//{three}")
  end

  it "expands from a Struct" do
    values = Struct.new(:a, :b).new("1", "2")
    expect(
      Addressable::Template.new("{a}{b}").expand(values).to_str
    ).to eq("12")
  end

  it "still expands from an array of pairs" do
    expect(
      Addressable::Template.new("{a}{b}").expand([["a", "1"], [:b, "2"]]).to_str
    ).to eq("12")
  end

  it "raises an error for both a mapping and a block" do
    expect do
      Addressable::Template.new("{a}").expand("a" => "1") { |name| name }
    end.to raise_error(ArgumentError)
    expect do
      Addressable::Template.new("{a}").partial_expand("a" => "1") { |n| n }
    end.to raise_error(ArgumentError)
  end

  it "raises an error for neither a mapping nor a block" do
    expect do
      Addressable::Template.new("{a}").expand
    end.to raise_error(ArgumentError)
    expect do
      Addressable::Template.new("{a}").partial_expand
    end.to raise_error(ArgumentError)
  end

  [nil, 42, "a", :a, true].each do |mapping|
    it "raises an error for #{mapping.inspect} as a mapping" do
      expect do
        Addressable::Template.new("{a}").expand(mapping)
      end.to raise_error(TypeError)
      expect do
        Addressable::Template.new("{a}").partial_expand(mapping)
      end.to raise_error(TypeError)
    end
  end
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
      '{var:20}' => 'value', # RFC 6570 section 2.4.1
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
  # RFC 6570 section 2.4.1: max-length is 1 to 9999, with no leading zero.
  context "length outside the bounds" do
    it_behaves_like 'expands', {
      '{var:1}' => 'v',
      '{var:9999}' => 'value',
      '{var:3,semi}' => 'val,%3B'
    }

    {
      "/x{var:0}" => 2,
      "/x{var:00}" => 2,
      "/x{var:03}" => 2,
      "/x{var:10000}" => 2,
      "/x{var:99999999999999999999}" => 2,
      "/x{var:}" => 2,
      "/x{var:\u0661}" => 2,
      "/x{var:0,semi}" => 2,
      "/x{+var:0}" => 2,
      "{semi}/{var:05}" => 7
    }.each do |pattern, position|
      it "raises InvalidTemplateError when expanding #{pattern}" do
        template = Addressable::Template.new(pattern)
        expression = pattern[position..-1]
        message = "Invalid template expression #{expression.inspect} " \
          "at position #{position}"
        expect { template.expand(subject) }.to raise_error(
          Addressable::Template::InvalidTemplateError, message
        )
        expect { template.partial_expand("semi" => ";") }.to raise_error(
          Addressable::Template::InvalidTemplateError, message
        )
      end
    end

    it "doesn't treat the expression as a variable" do
      ["/x{var:0}", "/x{var:05}", "/x{var:10000}", "/x{var:0,semi}"].each do |pattern|
        expect(Addressable::Template.new(pattern).variables).to eq([])
      end
      expect(Addressable::Template.new("/x{var:9999}").variables).to eq(["var"])
    end

    it "raises when matching" do
      ["/x{var:0}/{semi}", "/x{var:10000}/{semi}"].each do |pattern|
        template = Addressable::Template.new(pattern)
        expect { template.extract("/x/a") }.to raise_error(
          Addressable::Template::InvalidTemplateError,
          /Invalid template expression "\{var:\d+\}" at position 2/
        )
      end
    end
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
  # copied as they are. The literals grammar allows only non-ASCII characters
  # to be encoded this way, so ASCII characters it leaves out are left as they
  # are, as most other implementations do.
  context "literals" do
    subject { {"var" => "value"} }
    it_behaves_like 'expands', {
      "caf\u00E9/{var}" => 'caf%C3%A9/value',
      "{var}/\u20AC" => 'value/%E2%82%AC',
      "\u{1D11E}{var}" => '%F0%9D%84%9Evalue',
      'x%20y/{var}' => 'x%20y/value',
      'x%20y{var}z%20w' => 'x%20yvaluez%20w',
      'a%2fb/{var}' => 'a%2fb/value',
      "http://example.com/{var}?a=b&c=d#e:f@g!$'()*+,;=" =>
        "http://example.com/value?a=b&c=d#e:f@g!$'()*+,;="
    }

    {
      "/this has spaces" => "/this has spaces",
      "x y/{var}" => "x y/value",
      "\"{var}" => "\"value",
      "{var}<" => "value<",
      "a>" => "a>",
      "a\\b" => "a\\b",
      "a^b" => "a^b",
      "a`b" => "a`b",
      "a|b" => "a|b",
      "a\tb" => "a\tb",
      "a\x7Fb" => "a\x7Fb",
      "50%off/{var}" => "50%off/value",
      "50%2/{var}" => "50%2/value",
      "%" => "%",
      "\u00E9 {var}" => "%C3%A9 value"
    }.each do |pattern, expansion|
      it "leaves an ASCII character outside the grammar in #{pattern.inspect}" do
        template = Addressable::Template.new(pattern)
        expect(template.expand(subject).to_s).to eq(expansion)
        expect(template.partial_expand({}).pattern).to eq(pattern)
      end
    end

    it "encodes only non-ASCII literals in a pattern that isn't UTF-8" do
      pattern = "a b\xE9/{var}".dup.force_encoding("ISO-8859-1")
      expect(Addressable::Template.new(pattern).expand(subject).to_s).to eq(
        "a b%E9/value"
      )
    end

    it "matches an ASCII character outside the grammar only as written" do
      template = Addressable::Template.new("a b/{var}")
      expect(template.extract("a b/value")).to eq("var" => "value")
      expect(template.extract("a%20b/value")).to eq(nil)
    end

    it "treats a single quote as a literal (RFC 6570 erratum 6937)" do
      template = Addressable::Template.new("'{var}'")
      expect(template.expand(subject).to_s).to eq("'value'")
      expect(template.partial_expand({}).pattern).to eq("'{var}'")
      expect(template.extract("'value'")).to eq(subject)
    end

    it "keeps literals as they are in a partial expansion" do
      template = Addressable::Template.new("caf\u00E9{var}/{other}")
      expect(template.partial_expand("var" => "1").pattern).to eq(
        "caf\u00E91/{other}"
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

    it "matches a percent sign as written" do
      template = Addressable::Template.new("/50%off/{var}")
      expect(template.extract("/50%off/value")).to eq("var" => "value")
      expect(template.extract("/50%25off/value")).to eq(nil)
    end

    it "raises when matching braces that don't start an expression" do
      ["x{a.*}/{var}", "x{a(}/{var}"].each do |pattern|
        template = Addressable::Template.new(pattern)
        expect { template.extract("x{a.*}/value") }.to raise_error(
          Addressable::Template::InvalidTemplateError,
          /Invalid template expression "\{a[.(]\*?\}" at position 1/
        )
      end
    end

    it "matches encoded braces as literal text" do
      template = Addressable::Template.new("x%7Ba%7D/{var}")
      expect(template.extract("x%7Ba%7D/value")).to eq("var" => "value")
      expect(template.extract("x{a}/value")).to eq(nil)
    end

    it "extracts the values from an expansion" do
      rng = Random.new(1741)
      literals = ["a", "/", "?", "&", "=", "'", "%2F", "\u00E9", "\u20AC"]
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
        extracted = template.extract(expanded)
        if expanded !~ valid || extracted != mapping
          wrong << [pattern, expanded, extracted]
        end
      end
      expect(wrong.first(5)).to eq([])
    end
  end

  # RFC 6570 section 3: an error in a template is indicated to the caller.
  # These are the negative tests from uri-templates/uritemplate-test.
  context "malformed templates" do
    subject {
      {
        "id" => "thing",
        "var" => "value",
        "hello" => "Hello World!",
        "with space" => "fail",
        " leading_space" => "Hi!",
        "trailing_space " => "Bye!",
        "empty" => "",
        "path" => "/foo/bar",
        "list" => ["red", "green", "blue"],
        "keys" => {"semi" => ";", "dot" => ".", "comma" => ","},
        "example" => "red",
        "searchTerms" => "uri templates",
        "~thing" => "some-user",
        "default-graph-uri" => [
          "http://www.example/book/", "http://www.example/papers/"
        ],
        "query" => "PREFIX dc: <http://purl.org/dc/elements/1.1/> " \
          "SELECT ?book ?who WHERE { ?book dc:creator ?who }"
      }
    }
    error = Addressable::Template::InvalidTemplateError

    {
      "{/id*" => [error, 'Unclosed template expression "{/id*" at position 0'],
      "/id*}" => [error, 'Unmatched "}" at position 4'],
      "{/?id}" => [error, 'Invalid template expression "{/?id}" at position 0'],
      "{var:prefix}" => [error],
      "{hello:2*}" => [error],
      "{??hello}" => [error],
      "{with space}" => [error],
      "{ leading_space}" => [error],
      "{trailing_space }" => [error],
      "{$var}" => [error],
      "{*keys?}" => [error],
      "{?empty=default,var}" => [error],
      "{var}{-prefix|/-/|var}" =>
        [error, 'Invalid template expression "{-prefix|/-/|var}" at position 5'],
      "?q={searchTerms}&amp;c={example:color?}" => [error],
      "x{?empty|foo=none}" => [error],
      "/h{#hello+}" => [error],
      "/h\#{hello+}" => [error],
      "{;keys:1*}" => [error],
      "?{-join|&|var,list}" => [error],
      "/people/{~thing}" => [error],
      "/{default-graph-uri}" => [error],
      "/sparql{?query,default-graph-uri}" => [error],
      "/sparql{?query){&default-graph-uri*}" => [error,
        'Invalid template expression "{?query){&default-graph-uri*}" ' \
        'at position 7'],
      "/resolution{?x, y}" => [error],
      "{var:0}" => [error],
      "{var:01}" => [error],
      "{var:10000}" => [error],
      "{var:}" => [error],
      "{x.}" => [error],
      "{x..y}" => [error],
      "{%2x}" => [error],
      "{}" => [error],
      "{{var}}" => [error],
      "{var}{" => [error, 'Unclosed template expression "{" at position 5'],
      "}{var}" => [error, 'Unmatched "}" at position 0'],
      "{!hello}" => [Addressable::Template::InvalidTemplateOperatorError,
        'Invalid template operator "!" in "{!hello}" at position 0'],
      "{=path}" => [Addressable::Template::InvalidTemplateOperatorError],
      "{|var*}" => [Addressable::Template::InvalidTemplateOperatorError],
      "{,var}" => [Addressable::Template::InvalidTemplateOperatorError],
      "/{@var}" => [Addressable::Template::InvalidTemplateOperatorError,
        'Invalid template operator "@" in "{@var}" at position 1']
    }.each do |pattern, (error_class, message)|
      it "raises #{error_class} when expanding #{pattern.inspect}" do
        template = Addressable::Template.new(pattern)
        expectation = [error_class, message].compact
        expect { template.expand(subject) }.to raise_error(*expectation)
        expect { template.partial_expand(subject) }.to raise_error(*expectation)
        expect { template.partial_expand({}) }.to raise_error(*expectation)
      end

      it "raises #{error_class} when matching #{pattern.inspect}" do
        template = Addressable::Template.new(pattern)
        expectation = [error_class, message].compact
        expect { template.match(pattern) }.to raise_error(*expectation)
        expect { template.match("/x") }.to raise_error(*expectation)
        expect { template.extract(pattern) }.to raise_error(*expectation)
      end

      it "raises #{error_class} when building a regexp for #{pattern.inspect}" do
        template = Addressable::Template.new(pattern)
        expectation = [error_class, message].compact
        expect { template.to_regexp }.to raise_error(*expectation)
        expect { template.source }.to raise_error(*expectation)
        expect { template.named_captures }.to raise_error(*expectation)
      end
    end

    it "raises when matching before looking at the URI" do
      template = Addressable::Template.new("/{id")
      error = Addressable::Template::InvalidTemplateError
      expect { template.match("http://[") }.to raise_error(error)
      expect { template.match("/\xA4".b) }.to raise_error(error)
      expect { template.match(Addressable::URI.parse("/1")) }.to raise_error(error)
      processor = Class.new { def self.match(name) ".*" end }
      expect { template.extract("/1", processor) }.to raise_error(error)
    end

    it "raises errors that are InvalidTemplateErrors" do
      expect(Addressable::Template::InvalidTemplateOperatorError.ancestors).to(
        include(Addressable::Template::InvalidTemplateError)
      )
      expect(Addressable::Template::InvalidTemplateError.ancestors).to(
        include(StandardError)
      )
    end

    it "still creates the template" do
      template = Addressable::Template.new("x{a.*}/{var}")
      expect(template.pattern).to eq("x{a.*}/{var}")
      expect(template.variables).to eq(["var"])
    end

    it "can be frozen, and still raises when matching" do
      template = Addressable::Template.new("x{a.*}/{var}").freeze
      expect(template).to be_frozen
      expect { template.extract("x{a.*}/value") }.to raise_error(
        Addressable::Template::InvalidTemplateError
      )
      expect { template.to_regexp }.to raise_error(
        Addressable::Template::InvalidTemplateError
      )
    end

    it "expands variable names the grammar allows" do
      template = Addressable::Template.new("{x.y}/{%41}/{a_1}{?b,c}{x.y:2}")
      expect(template.expand(
        "x.y" => "123", "%41" => "2", "a_1" => "3", "b" => "4", "c" => "5"
      ).to_str).to eq("123/2/3?b=4&c=512")
    end

    it "expands long templates with non-ASCII literals in linear time" do
      # Compared with ASCII literals on the same runner, so that a slow or
      # busy runner doesn't fail the spec. Scanning literals by character
      # offset, which is quadratic, took over ten times as long at this size.
      size = 50_000
      ascii = Addressable::Template.new("a{a}" * size)
      non_ascii = Addressable::Template.new("é{a}" * size)
      fastest = lambda do |template|
        3.times.map do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          template.expand("a" => "x")
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        end.min
      end
      expect(non_ascii.expand("a" => "x").to_str).to eq("%C3%A9x" * size)
      ascii_time = fastest.call(ascii)
      non_ascii_time = fastest.call(non_ascii)
      expect(non_ascii_time).to be < (ascii_time * 4) + 0.05
    end

    it "checks long templates in linear time" do
      [
        "{" * 100_000,
        "}" * 100_000,
        "{a" * 50_000,
        "{" + ("a." * 50_000) + "}",
        "{" + ("a," * 50_000) + "!}",
        "{" + ("%2" * 50_000) + "}",
        ("{a}" * 30_000) + "{",
        ("é{a}" * 30_000) + "}",
        ("é" * 100_000) + "{é}"
      ].each do |pattern|
        template = Addressable::Template.new(pattern)
        expect do
          Timeout.timeout(10) do
            expect { template.expand({}) }.to raise_error(
              Addressable::Template::InvalidTemplateError
            )
          end
        end.not_to raise_error
      end
    end
  end

  # RFC 6570 section 2.4.1: prefix modifiers don't apply to composite values.
  context "prefix modifiers on composite values" do
    subject {
      {
        "var" => "value",
        "list" => ["red", "green"],
        "keys" => {"semi" => ";", "dot" => "."},
        "empty_list" => [],
        "nil_list" => [nil],
        "empty_keys" => {}
      }
    }

    ["{list:1}", "{+list:4}", "{#list:2}", "{?list:3}", "{/var,list:1}",
      "{keys:1}", "{+keys:1}", "{;keys:2}", "{&keys:9999}"].each do |pattern|
      it "raises InvalidTemplateValueError when expanding #{pattern}" do
        template = Addressable::Template.new(pattern)
        expect { template.expand(subject) }.to raise_error(
          Addressable::Template::InvalidTemplateValueError,
          /prefix modifier :\d+ can't be applied to the list or associative array "(list|keys)"/
        )
        expect { template.partial_expand(subject) }.to raise_error(
          Addressable::Template::InvalidTemplateValueError
        )
      end
    end

    it_behaves_like 'expands', {
      '{var:3}' => 'val',
      '{list}' => 'red,green',
      '{keys*}' => 'semi=%3B,dot=.',
      'x{empty_list:1}' => 'x',
      'x{nil_list:1}' => 'x',
      'x{?empty_keys:1}' => 'x',
      'x{undefined:1}' => 'x'
    }

    it "leaves the expression in a partial expansion without the value" do
      template = Addressable::Template.new("{list:1}/{var}")
      expect(template.partial_expand("var" => "v").pattern).to eq("{list:1}/v")
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
        # The fragment's own "#" comes first, so any "#" in the value is
        # encoded.
        if fragment.expand("value" => value).to_s !=
            "#" + expanded.gsub("#", "%23")
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

    it "isn't changed by changing the variables it returned" do
      subject.freeze
      subject.variables.clear
      subject.keys << "third"
      subject.names.push("fourth")
      expect(subject.variables).to eq(["first", "second"])
    end
  end

  describe "variables" do
    subject { Addressable::Template.new("http://example.com/{first}/{+second}/") }

    it "isn't changed by changing an earlier result" do
      subject.variables.clear
      subject.keys << "third"
      subject.names.push("fourth")
      expect(subject.variables).to eq(["first", "second"])
      expect(subject.match("http://example.com/a/b/").mapping).to eq(
        "first" => "a", "second" => "b"
      )
    end
  end

  describe "variable_defaults" do
    subject { Addressable::Template.new("http://example.com/{first}/") }

    it "isn't changed by changing an earlier result" do
      subject.variable_defaults["first"] = "default"
      expect(subject.variable_defaults).to eq({})
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
    context "partial_expand with every variable of a comma expression" do
      {
        "{one,two}" => "1,2",
        "{+one,two}" => "1,2",
        "{#one,two}" => "#1,2"
      }.each do |pattern, expected|
        it "expands #{pattern} as a whole" do
          template = Addressable::Template.new(pattern)
          expect(template.partial_expand(one: "1", two: "2").pattern).to eq(
            expected
          )
        end
      end
    end
    # These specs document how partial expansion behaves, not what's
    # strictly correct. RFC 6570 has no expression that writes a "," only if
    # a missing variable is given a value later, so the result is right if
    # the missing variables stay undefined, and has one comma too few for
    # each that's given a value later. The specs pin both outcomes, so that a
    # change to either is deliberate.
    context "partial_expand with some variables of a comma expression" do
      {
        ["{one,two,three}", {two: "2", three: "3"}, {one: "1"}] =>
          ["{one}2,3", "12,3", "1,2,3"],
        ["{+one,two,three}", {one: "1", three: "3"}, {two: "2"}] =>
          ["1{+two},3", "12,3", "1,2,3"],
        ["{#one,two}", {one: "1"}, {two: "2"}] => ["#1{+two}", "#12", "#1,2"],
        ["{#one,two}", {two: "2"}, {one: "1"}] => ['#{+one}2', "#12", "#1,2"]
      }.each do |(pattern, mapping, later), (expected, incomplete, correct)|
        it "keeps the separator between given values in #{pattern}, " \
            "but not before a missing one" do
          template = Addressable::Template.new(pattern)
          expect(template.partial_expand(mapping).pattern).to eq(expected)
          expect(Addressable::Template.new(expected).expand({}).to_str).to eq(
            template.expand(mapping).to_str
          )
          # Wrong: expanding all at once gives the correct one.
          partial = Addressable::Template.new(expected)
          expect(partial.expand(later).to_str).to eq(incomplete)
          expect(template.expand(mapping.merge(later)).to_str).to eq(correct)
        end
      end
    end
    context "issue #307 - partial_expand form query with nil params" do
      subject do
        Addressable::Template.new("http://example.com/{?one,two,three}/")
      end
      it "builds a new pattern with two=nil" do
        expect(subject.partial_expand(two: nil).pattern).to eq(
          "http://example.com/{?one,three}/"
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
          "http://example.com/{?two,three}/"
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

      it "encodes the bytes of input that isn't valid UTF-8" do
        template = subject.partial_expand("query" => "M\xE9thode".b)
        expect(template.pattern).to eq(
          "http://example.com/{resource}/M%E9thode/"
        )
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

      it "encodes the bytes of input that isn't valid UTF-8" do
        uri = subject.expand("query" => "M\xE9thode".b).to_str
        expect(uri).to eq("http://example.com/search/M%E9thode/")
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

  it "isn't changed by changing the values it returned" do
    its.values.clear
    its.captures << "ef"
    expect(its.values).to eq(['ab', 'cd'])
    expect(its.to_a).to eq(['ab/cd', 'ab', 'cd'])
  end

  it "doesn't change the template by changing the variables it returned" do
    its.variables.clear
    its.keys << "baz"
    expect(its.names).to eq(['foo', 'bar'])
    expect(template.variables).to eq(['foo', 'bar'])
  end

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

describe Addressable::Template, "with a number sign after the fragment starts" do
  {
    ["x{#var}", {"var" => "a#b"}] => "x#a%23b",
    ["{+var}", {"var" => "p#q#r"}] => "p#q%23r",
    ["{+base}{#frag}", {"base" => "p#q", "frag" => "r"}] => "p#q%23r",
    ['x#a#{var}', {"var" => "v"}] => "x#a%23v",
    ["{#a}{#b}", {"a" => "p", "b" => "q"}] => "#p%23q",
    ["x{#var}", {"var" => "a%23b"}] => "x#a%23b",
    ["x{#var}", {"var" => "b"}] => "x#b",
    ["{var}", {"var" => "p#q"}] => "p%23q",
    ["/x{?q}{#var}", {"q" => "a#b", "var" => "c#d"}] => "/x?q=a%23b#c%23d"
  }.each do |(pattern, mapping), expected|
    context "expanding #{pattern} with #{mapping.inspect}" do
      subject { Addressable::Template.new(pattern) }

      it "encodes every number sign after the first as %23" do
        expect(subject.expand(mapping).to_s).to eq(expected)
      end

      it "matches the expansion and expands the result to the same URI" do
        extracted = subject.extract(expected)
        expect(extracted).not_to be_nil
        expect(subject.expand(extracted.reject { |_, v| v.nil? }).to_s).to eq(
          expected
        )
      end
    end
  end

  it "returns a URI whose fragment holds the encoded number sign" do
    uri = Addressable::Template.new("x{#var}").expand("var" => "a#b")
    expect(uri.fragment).to eq("a%23b")
  end

  it "leaves the number signs in a partially expanded pattern as they are" do
    template = Addressable::Template.new("x#a{+var}{#frag}")
    partial = template.partial_expand("var" => "b#c")
    expect(partial.pattern).to eq("x#ab#c{#frag}")
    expect(partial.expand("frag" => "d").to_s).to eq("x#ab%23c%23d")
    expect(template.expand("var" => "b#c", "frag" => "d").to_s).to eq(
      "x#ab%23c%23d"
    )
  end

  it "matches a literal number sign after the first either way" do
    template = Addressable::Template.new('x#a#{var}')
    expect(template.extract("x#a%23v")).to eq("var" => "v")
    expect(template.extract("x#a#v")).to eq("var" => "v")
  end

  it "matches a fragment leader after the first either way" do
    template = Addressable::Template.new("x#a{#var}")
    expect(template.extract("x#a%23v")).to eq("var" => "v")
    expect(template.extract("x#a#v")).to eq("var" => "v")
  end

  it "matches a literal number sign after reserved expansion either way" do
    template = Addressable::Template.new("{+base}#x")
    expect(template.extract("p#q%23x")).to eq("base" => "p#q")
    expect(template.extract("p#x")).to eq("base" => "p")
  end

  it "doesn't take %23 for the number sign that starts the fragment" do
    expect(Addressable::Template.new('/p#{var}').extract("/p%23x")).to be_nil
    expect(Addressable::Template.new("/p{#var}").extract("/p%23x")).to be_nil
  end

  it "doesn't take %23 for a number sign before any fragment" do
    template = Addressable::Template.new("/{var}#x")
    expect(template.extract("/v%23x")).to be_nil
    expect(template.extract("/v#x")).to eq("var" => "v")
  end
end

describe Addressable::Template, "with values pct-encoded at several levels" do
  # Each value is followed by what extraction gives back from its expansion
  # in reserved and fragment expansion: the text of the URI, pct-decoded
  # once, since those operators keep a value's pct-encoded triplets.
  reserved = {
    "a/b" => "a/b",
    "a%2Fb" => "a/b",
    "a%252Fb" => "a%2Fb",
    "a%25252Fb" => "a%252Fb",
    "%" => "%",
    "%25" => "%",
    "%2525" => "%25",
    "%41" => "A",
    "%2541" => "%41",
    "%252541" => "%2541",
    "a%20b" => "a b",
    "a%2520b" => "a%20b",
    "caf%C3%A9" => "café",
    "caf%25C3%25A9" => "caf%C3%A9",
    "%25%2F" => "%/",
    "%2F%252F" => "/%2F",
    "a#b" => "a#b",
    "a%23b" => "a#b",
    "%3Ab" => ":b",
    "%253Ab" => "%3Ab"
  }

  ["/x{var}", "/x{/var}", "/x{.var}", "/x{;var}", "/x{?var}",
    "/x?y=1{&var}"].each do |pattern|
    context "with #{pattern}" do
      subject { Addressable::Template.new(pattern) }

      reserved.keys.each do |value|
        it "gives #{value.inspect} back and keeps the URI over three cycles" do
          uri = subject.expand("var" => value).to_s
          expect(subject.extract(uri)).to eq("var" => value)
          3.times do
            uri_again = subject.expand(subject.extract(uri)).to_s
            expect(uri_again).to eq(uri)
            uri = uri_again
          end
        end
      end
    end
  end

  ["/x{+var}", "/x{#var}"].each do |pattern|
    context "with #{pattern}" do
      subject { Addressable::Template.new(pattern) }

      reserved.each do |value, extracted|
        it "gives #{extracted.inspect} for #{value.inspect}" do
          uri = subject.expand("var" => value).to_s
          expect(subject.extract(uri)).to eq("var" => extracted)
        end
      end
    end
  end

  it "can give a different URI when a reserved expansion is expanded again" do
    template = Addressable::Template.new("/files/{+path}")
    extracted = template.extract("/files/a%2Fb")
    expect(extracted).to eq("path" => "a/b")
    expect(template.expand(extracted).to_s).to eq("/files/a/b")
    expect(template.extract("/files/a%252Fb")).to eq("path" => "a%2Fb")
    expect(template.expand("path" => "a%2Fb").to_s).to eq("/files/a%2Fb")
  end

  it "doesn't decode values when a processor only responds to match" do
    processor = Class.new do
      def self.match(_name)
        ".*?"
      end
    end
    template = Addressable::Template.new("/search/{q}")
    uri = "/search/caf%C3%A9%20au%20lait"
    expect(template.extract(uri)).to eq("q" => "caf\u00E9 au lait")
    expect(template.extract(uri, processor)).to eq(
      "q" => "caf%C3%A9%20au%20lait"
    )
  end

  it "gives a processor each value as it appears in the URI" do
    processor = Class.new do
      def self.restore(_name, value)
        value
      end
    end
    template = Addressable::Template.new("/files/{+path}{?q}")
    expect(template.extract("/files/a%2Fb%252F?q=c%20d", processor)).to eq(
      "path" => "a%2Fb%252F", "q" => "c%20d"
    )
  end
end

describe Addressable::Template, "with a name that starts with a digit" do
  # RFC 6570 section 2.3 allows a digit as the first character of a name,
  # which a Ruby regular expression group name can't start with. Ruby 2.3
  # and earlier only allow a letter or "_" as its first character.
  dot_allowed = Addressable::Template.const_get(:GROUP_NAME_CAN_START_WITH_DOT)
  group = lambda { |name| dot_allowed ? ".#{name}" : "__#{name}__" }

  {
    "/{42}" => [{"42" => "x"}, "/x"],
    "/{1x}" => [{"1x" => "x"}, "/x"],
    "/{1x.y}" => [{"1x.y" => "x"}, "/x"],
    "/{42}{?q}" => [{"42" => "x", "q" => "y"}, "/x?q=y"]
  }.each do |pattern, (mapping, uri)|
    context "in #{pattern}" do
      subject { Addressable::Template.new(pattern) }

      it "lists its variables" do
        expect(subject.variables).to eq(mapping.keys)
        expect(subject.keys).to eq(mapping.keys)
        expect(subject.variable_defaults).to eq({})
      end

      it "extracts and matches its expansion" do
        expect(subject.expand(mapping).to_s).to eq(uri)
        expect(subject.extract(uri)).to eq(mapping)
        expect(subject.match(uri).mapping).to eq(mapping)
      end

      it "names its captures after the variables" do
        expect(subject.named_captures.keys).to eq(mapping.keys)
      end

      it "can be frozen" do
        expect(subject.freeze).to be_frozen
      end

      it "gives a regular expression with a group for the name" do
        match = subject.to_regexp.match(uri)
        mapping.each_key do |name|
          next unless name =~ /\A\d/
          expect(match[group.call(name)]).to eq(mapping[name])
        end
      end
    end
  end

  it "keeps a name that starts with a digit apart from every other name" do
    template = Addressable::Template.new("/{42}/{_42}")
    expect(template.extract("/a/b")).to eq("42" => "a", "_42" => "b")
    match = template.to_regexp.match("/a/b")
    expect(match[group.call("42")]).to eq("a")
    expect(match["_42"]).to eq("b")
  end
end

describe Addressable::Template, "with a name that has a dot or a triplet" do
  # RFC 6570 section 2.3 allows "." between characters of a variable name
  # and pct-encoded triplets in it. Ruby 2.3 and earlier only allow a letter
  # or "_" as the first character of a group name, so there a name that
  # starts with a triplet has its group wrapped in "__".
  dot_allowed = Addressable::Template.const_get(:GROUP_NAME_CAN_START_WITH_DOT)
  group = lambda do |name|
    dot_allowed || name =~ /\A[A-Za-z_]/ ? name : "__#{name}__"
  end

  {
    "/{a.b}" => [{"a.b" => "x"}, "/x"],
    "/{a%20b}" => [{"a%20b" => "x"}, "/x"],
    "/{x.y}/{%41}{?q}" => [{"x.y" => "x", "%41" => "y", "q" => "z"}, "/x/y?q=z"]
  }.each do |pattern, (mapping, uri)|
    context "in #{pattern}" do
      subject { Addressable::Template.new(pattern) }

      it "lists its variables" do
        expect(subject.variables).to eq(mapping.keys)
        expect(subject.keys).to eq(mapping.keys)
        expect(subject.variable_defaults).to eq({})
      end

      it "extracts and matches its expansion" do
        expect(subject.expand(mapping).to_s).to eq(uri)
        expect(subject.extract(uri)).to eq(mapping)
        expect(subject.match(uri).mapping).to eq(mapping)
      end

      it "names its regular expression groups after the variables" do
        expect(subject.to_regexp.names).to eq(mapping.keys.map(&group))
        expect(subject.named_captures.keys).to eq(mapping.keys)
      end

      it "can be frozen" do
        expect(subject.freeze).to be_frozen
      end
    end
  end
end

describe Addressable::Template, "with text that isn't valid UTF-8" do
  invalid = "\xA4".dup.force_encoding("UTF-8")

  # Each byte that isn't valid UTF-8 is pct-encoded as it is.
  {
    "{a}" => "/x%A4", "{+a}" => "/x%A4", "{#a}" => "/x#%A4",
    "{/a}" => "/x/%A4", "{.a}" => "/x.%A4", "{;a}" => "/x;a=%A4",
    "{?a}" => "/x?a=%A4", "{&a}" => "/x&a=%A4", "{a*}" => "/x%A4",
    "{a:2}" => "/x%A4"
  }.each do |expression, expected|
    it "expands #{expression} with a value that isn't valid UTF-8" do
      template = Addressable::Template.new("/x#{expression}")
      expect(template.expand("a" => invalid).to_s).to eq(expected)
    end
  end

  it "expands a binary value that isn't valid UTF-8" do
    template = Addressable::Template.new("/x{a}")
    expect(template.expand("a" => "\xA4".b).to_s).to eq("/x%A4")
  end

  it "expands lists and hashes with values that aren't valid UTF-8" do
    expect(
      Addressable::Template.new("/x{a}").expand("a" => [invalid, "b"]).to_s
    ).to eq("/x%A4,b")
    expect(
      Addressable::Template.new("/x{?a*}").expand("a" => {"k" => invalid}).to_s
    ).to eq("/x?k=%A4")
  end

  it "partially expands a value that isn't valid UTF-8" do
    template = Addressable::Template.new("/x{a}{b}")
    expect(template.partial_expand("a" => invalid).pattern).to eq("/x%A4{b}")
  end

  # RFC 6570 section 3.2.1: a value in another character encoding is
  # transcoded to UTF-8 before it's pct-encoded.
  {
    "ISO-8859-1" => ["M\u00E9thode", "M%C3%A9thode"],
    "Windows-1252" => ["\u20AC5", "%E2%82%AC5"],
    "Shift_JIS" => ["\u65E5\u672C", "%E6%97%A5%E6%9C%AC"],
    "UTF-16LE" => ["a/\u00E9", "a%2F%C3%A9"]
  }.each do |encoding, (text, expected)|
    it "transcodes a #{encoding} value to UTF-8" do
      template = Addressable::Template.new("/x{a}")
      value = text.encode(encoding)
      expect(template.expand("a" => value).to_s).to eq("/x#{expected}")
    end
  end

  it "transcodes before taking a prefix" do
    template = Addressable::Template.new("/x{a:2}")
    value = "\u00E9t\u00E9".encode("ISO-8859-1")
    expect(template.expand("a" => value).to_s).to eq("/x%C3%A9t")
  end

  it "transcodes keys and values of an associative array" do
    template = Addressable::Template.new("/x{?a*}")
    value = {"\u00E9".encode("ISO-8859-1") => "\u00E8".encode("ISO-8859-1")}
    expect(template.expand("a" => value).to_s).to eq("/x?%C3%A9=%C3%A8")
  end

  it "transcodes a value when partially expanding" do
    template = Addressable::Template.new("/x{a}{b}")
    value = "\u00E9".encode("ISO-8859-1")
    expect(template.partial_expand("a" => value).pattern).to eq("/x%C3%A9{b}")
  end

  it "encodes the bytes of a value that isn't valid in its own encoding" do
    template = Addressable::Template.new("/x{a}")
    value = "\x81".dup.force_encoding("Shift_JIS")
    expect(template.expand("a" => value).to_s).to eq("/x%81")
  end

  it "takes a reserved prefix of a value that isn't valid UTF-8" do
    template = Addressable::Template.new("/x{+a:2}")
    expect(template.expand("a" => invalid + "%2Fc").to_s).to eq("/x%A4%2F")
  end

  it "still normalizes a value that is valid UTF-8" do
    template = Addressable::Template.new("/x{a}")
    expect(template.expand("a" => "é").to_s).to eq("/x%C3%A9")
  end

  it "expands an extracted value that isn't valid UTF-8 to the same URI" do
    template = Addressable::Template.new("/x{a}")
    extracted = template.extract("/x%A4")
    expect(extracted["a"].bytes).to eq([0xA4])
    expect(template.expand(extracted).to_s).to eq("/x%A4")
  end

  {
    "binary" => "/x\xFF".b,
    "UTF-8" => "/x\xFF".dup.force_encoding("UTF-8"),
    "ISO-8859-1" => "/x\xE9".dup.force_encoding("ISO-8859-1")
  }.each do |label, uri|
    it "doesn't match a #{label} URI that isn't valid UTF-8" do
      template = Addressable::Template.new("/x{a}")
      expect(template.match(uri)).to be_nil
      expect(template.extract(uri)).to be_nil
    end
  end

  it "doesn't match a parsed URI that isn't valid UTF-8" do
    uri = Addressable::URI.parse("/x\xFF".b)
    expect(Addressable::Template.new("/x{a}").extract(uri)).to be_nil
  end

  it "still matches a binary URI that is valid UTF-8" do
    template = Addressable::Template.new("/x{a}")
    expect(template.extract("/caf\xC3\xA9".b.sub("/caf", "/x"))).to eq(
      "a" => "é"
    )
  end
end

describe Addressable::Template, "extracting an exploded named list" do
  # An exploded list in ;, ? or & expansion repeats the variable's name,
  # where an associative array uses its own keys (RFC 6570 section 3.2.1).
  {
    ["{?a*}", "?a=x&a=y"] => {"a" => ["x", "y"]},
    ["{?a*}", "?a=x&a=y&a=z"] => {"a" => ["x", "y", "z"]},
    ["{?a*}", "?a=x"] => {"a" => ["x"]},
    ["{&a*}", "&a=x&a=y"] => {"a" => ["x", "y"]},
    ["{;a*}", ";a=x;a=y"] => {"a" => ["x", "y"]},
    ["{;a*}", ";a;a=y"] => {"a" => ["", "y"]},
    ["{?a*}", "?a=x%20y&a=c%26d"] => {"a" => ["x y", "c&d"]},
    ["/p{?q,a*}", "/p?q=1&a=x&a=y"] => {"q" => "1", "a" => ["x", "y"]}
  }.each do |(pattern, uri), mapping|
    it "extracts #{mapping.inspect} from #{uri} with #{pattern}" do
      template = Addressable::Template.new(pattern)
      expect(template.extract(uri)).to eq(mapping)
      expect(template.expand(mapping).to_s).to eq(uri)
    end
  end

  {
    ["{?a*}", "?k=v&l=w"] => {"a" => {"k" => "v", "l" => "w"}},
    ["{?a*}", "?a=1&b=2"] => {"a" => {"a" => "1", "b" => "2"}},
    ["{;a*}", ";k=v;l=w"] => {"a" => {"k" => "v", "l" => "w"}}
  }.each do |(pattern, uri), mapping|
    it "still extracts an associative array #{mapping.inspect} from #{uri}" do
      expect(Addressable::Template.new(pattern).extract(uri)).to eq(mapping)
    end
  end

  it "compares each key with the variable's name as written" do
    template = Addressable::Template.new("{?a*}")
    expect(template.extract("?%61=x")).to eq("a" => {"a" => "x"})
    expect(template.extract("?a=x&%61=y")).to eq("a" => {"a" => "y"})
    template = Addressable::Template.new("{?a%20b*}")
    expect(template.extract("?a%20b=x&a%20b=y")).to eq("a%20b" => ["x", "y"])
  end

  it "keeps a value's \"=\" in an exploded list or associative array" do
    expect(Addressable::Template.new("{?a*}").extract("?a=x=y&a=z")).to eq(
      "a" => ["x=y", "z"]
    )
    expect(Addressable::Template.new("{?a*}").extract("?k=x=y")).to eq(
      "a" => {"k" => "x=y"}
    )
  end
end

describe Addressable::Template, "expanding empty members with ;" do
  # RFC 6570 appendix A: an exploded member or pair whose value is empty
  # gets the operator's ifemp string, which is empty for ";".
  {
    ["{;a*}", {"a" => ["", "y"]}] => ";a;a=y",
    ["{;a*}", {"a" => [""]}] => ";a",
    ["{;a*}", {"a" => {"k" => "", "l" => "v"}}] => ";k;l=v",
    ["{;a*}", {"a" => {"k" => "v", "l" => ""}}] => ";k=v;l",
    ["{;a,b*}", {"a" => "", "b" => ["", "z"]}] => ";a;b;b=z",
    ["{;a}", {"a" => ["", "y"]}] => ";a=,y",
    ["{?a*}", {"a" => ["", "y"]}] => "?a=&a=y",
    ["{?a*}", {"a" => {"k" => ""}}] => "?k=",
    ["{&a*}", {"a" => ["", "y"]}] => "&a=&a=y"
  }.each do |(pattern, mapping), expected|
    it "expands #{pattern} with #{mapping.inspect} to #{expected}" do
      template = Addressable::Template.new(pattern)
      expect(template.expand(mapping).to_s).to eq(expected)
    end
  end

  it "expands empty exploded members the same way when partially expanding" do
    template = Addressable::Template.new("{;a*}{?b}")
    partial = template.partial_expand("a" => ["", "y"])
    expect(partial.pattern).to eq(";a;a=y{?b}")
  end

  it "extracts the members again" do
    template = Addressable::Template.new("{;a*}")
    expect(template.extract(";a;a=y")).to eq("a" => ["", "y"])
    expect(template.extract(";k;l=v")).to eq("a" => {"k" => "", "l" => "v"})
  end
end

describe Addressable::Template, "expanding a list with one empty member" do
  # RFC 6570 section 3.2.7 appends "=" unless the variable's value is
  # empty, and a list is undefined, not empty, when it has no members
  # (section 2.3), so a list whose only member is empty still gets "=".
  {
    ["{;a}", {"a" => [""]}] => ";a=",
    ["{;a}", {"a" => ["", nil]}] => ";a=",
    ["{;a,b}", {"a" => [""], "b" => "x"}] => ";a=;b=x",
    ["{;a}", {"a" => ""}] => ";a",
    ["{;a}", {"a" => ["", ""]}] => ";a=,",
    ["{;a}", {"a" => []}] => "",
    ["{?a}", {"a" => [""]}] => "?a=",
    ["{&a}", {"a" => [""]}] => "&a=",
    ["{;a*}", {"a" => [""]}] => ";a"
  }.each do |(pattern, mapping), expected|
    it "expands #{pattern} with #{mapping.inspect} to #{expected.inspect}" do
      template = Addressable::Template.new(pattern)
      expect(template.expand(mapping).to_s).to eq(expected)
    end
  end

  it "expands it the same way when partially expanding" do
    template = Addressable::Template.new("{;a}{?b}")
    expect(template.partial_expand("a" => [""]).pattern).to eq(";a={?b}")
  end
end

# These specs document how partial expansion behaves, not what's strictly
# correct. RFC 6570 has no expression that writes a "," only if a missing
# variable is given a value later, so a partial result matches expanding all
# at once only if the missing variables stay undefined. The specs pin the
# result of giving them values later too, next to the correct one, so that a
# change to either is deliberate.
describe Addressable::Template, "partially expanding a fragment expression" do
  full = {"x" => "1", "hello" => "H", "y" => "2"}

  # Once a given variable is defined, the expression's "#" is certain, so it
  # comes first, once, and the missing variables continue with reserved
  # expansion. The "#" is right in every case; the commas aren't.
  {
    {"hello" => "H"} => ['#{+x}H{+y}', "#1H2"],
    {"hello" => "H", "y" => "2"} => ['#{+x}H,2', "#1H,2"],
    {"y" => "2"} => ['#{+x,hello}2', "#1,H2"],
    {"x" => "1"} => ['#1{+hello,y}', "#1H,2"],
    {"hello" => ""} => ['#{+x}{+y}', "#12"]
  }.each do |given, (pattern, incomplete)|
    it "gives #{pattern} for {#x,hello,y} with #{given.inspect}, which " \
        "matches expanding all at once only if the rest stay undefined" do
      template = Addressable::Template.new("{#x,hello,y}")
      partial = template.partial_expand(given)
      expect(partial.pattern).to eq(pattern)
      expect(partial.expand({}).to_s).to eq(template.expand(given).to_s)
      rest = full.reject { |name, _| given.key?(name) }
      expect(partial.expand(rest).to_s.count("#")).to eq(1)
      expect(partial.expand(rest).to_s).not_to include("%23")
      # Wrong: expanding all at once gives the correct one.
      expect(partial.expand(rest).to_s).to eq(incomplete)
      expect(partial.expand(rest).to_s).not_to eq(
        template.expand(given.merge(rest)).to_s
      )
    end
  end

  it "keeps the missing variables around an undefined one together" do
    template = Addressable::Template.new("{#x,hello,y}")
    partial = template.partial_expand("hello" => nil)
    expect(partial.pattern).to eq("{#x,y}")
    expect(partial.expand("x" => "1", "y" => "2").to_s).to eq("#1,2")
    expect(partial.expand({}).to_s).to eq("")
  end
end

describe Addressable::Template, "partially expanding around an undefined variable" do
  # An undefined variable adds nothing, so the missing variables on either
  # side of it stay in one expression and keep their separator.
  {
    "{x,hello,y}" => ["{x,y}", "1,2"],
    "{+x,hello,y}" => ["{+x,y}", "1,2"],
    "{/x,hello,y}" => ["{/x,y}", "/1/2"],
    "{.x,hello,y}" => ["{.x,y}", ".1.2"],
    "{;x,hello,y}" => ["{;x,y}", ";x=1;y=2"]
  }.each do |pattern, (partial_pattern, expanded)|
    it "gives #{partial_pattern} for #{pattern} with hello undefined" do
      partial = Addressable::Template.new(pattern).partial_expand("hello" => nil)
      expect(partial.pattern).to eq(partial_pattern)
      expect(partial.expand("x" => "1", "y" => "2").to_s).to eq(expanded)
    end
  end
end

describe Addressable::Template, "extracting a label value that contains a dot" do
  # Label expansion leaves a "." in a value as it is, which adds labels
  # (RFC 6570 section 3.2.5), so where a value ends is only known where the
  # expression is delimited by the start or end of the URI or by characters
  # that can't be part of its expansion (section 1.4). A lone label variable
  # delimited that way can take the dots.
  {
    ["/f{.ext}", "/f.tar.gz"] => {"ext" => "tar.gz"},
    ["{.a}", ".A.B"] => {"a" => "A.B"},
    ["X{.var}", "X.a.b"] => {"var" => "a.b"},
    ["/f{.ext}", "/f.t%C3%A9.gz"] => {"ext" => "té.gz"},
    ["/f{.ext}/raw", "/f.tar.gz/raw"] => {"ext" => "tar.gz"},
    ["/f{.ext};v", "/f.tar.gz;v"] => {"ext" => "tar.gz"},
    ["/f{.ext}#top", "/f.tar.gz#top"] => {"ext" => "tar.gz"},
    ["/f{.ext}{?q}", "/f.tar.gz?q=1"] => {"ext" => "tar.gz", "q" => "1"},
    ["/f{.ext}{&q}", "/f.tar.gz&q=1"] => {"ext" => "tar.gz", "q" => "1"},
    ["/f{.ext}{;q}", "/f.tar.gz;q=1"] => {"ext" => "tar.gz", "q" => "1"},
    ["/f{.ext}{#s}", "/f.tar.gz#x"] => {"ext" => "tar.gz", "s" => "x"},
    ["/f{.ext}{/y}", "/f.tar.gz/z"] => {"ext" => "tar.gz", "y" => "z"},
    ["/f{.ext}{/y}{?q}", "/f.tar.gz"] =>
      {"ext" => "tar.gz", "y" => nil, "q" => nil},
    ["{+base}/f{.ext}", "x/f.a/f.b.c"] => {"base" => "x/f.a", "ext" => "b.c"}
  }.each do |(pattern, uri), mapping|
    it "extracts #{mapping.inspect} from #{uri} with #{pattern}" do
      template = Addressable::Template.new(pattern)
      expect(template.extract(uri)).to eq(mapping)
      expect(template.expand(mapping).to_s).to eq(uri)
    end
  end

  # Elsewhere, a "." could end the value or start the next label, so each
  # "." is still read as starting a label. These results aren't the only
  # reading of the URI, and for some of them none is found.
  {
    ["/{name}{.ext}", "/archive.tar.gz"] =>
      {"name" => "archive.tar", "ext" => "gz"},
    ["/f{.ext}{/y}.bak", "/f.gz.bak"] => {"ext" => "gz", "y" => nil},
    ["/f{.ext}{/y}.bak", "/f.tar.gz.bak"] => nil,
    ["/f{.ext}.bak", "/f.tar.gz.bak"] => nil,
    ["/f{.ext}{+r}", "/f.tar.gz/x"] => {"ext" => nil, "r" => ".tar.gz/x"},
    ["{.a}{.b}", ".x.y.z"] => nil,
    ["{.a,b}", ".A.B.C"] => nil,
    ["{.a*}", ".A.B.C"] => {"a" => ["A", "B", "C"]},
    # Once a fragment may have started, a later "#" can be "%23", which a
    # label value could contain.
    ["#a{.ext}#b", "#a.gz%23b"] => {"ext" => "gz"},
    ["#a{.ext}#b", "#a.tar.gz%23b"] => nil,
    ["#a{.ext}{#s}", "#a.gz%23x"] => {"ext" => "gz", "s" => "x"},
    ["#a{.ext}{#s}", "#a.tar.gz%23x"] => nil
  }.each do |(pattern, uri), mapping|
    it "extracts #{mapping.inspect} from #{uri} with #{pattern}" do
      expect(Addressable::Template.new(pattern).extract(uri)).to eq(mapping)
    end
  end

  it "matches a long run of labels in linear time" do
    template = Addressable::Template.new("/f{.ext}")
    expect do
      Timeout.timeout(10) do
        expect(template.match("/f" + (".a" * 50_000) + "!")).to be_nil
        expect(template.extract("/f" + (".a" * 50_000))).to eq(
          "ext" => ("a." * 50_000).chop
        )
      end
    end.not_to raise_error
  end
end
