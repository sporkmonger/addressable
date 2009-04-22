# encoding:utf-8
#--
# Addressable, Copyright (c) 2006-2007 Bob Aman
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

$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../../lib'))
$:.uniq!

require "addressable/uri"
require "addressable/template"

if !"".respond_to?("force_encoding")
  class String
    def force_encoding(encoding)
      @encoding = encoding
    end

    def encoding
      @encoding ||= Encoding::ASCII_8BIT
    end
  end

  class Encoding
    def initialize(name)
      @name = name
    end

    def to_s
      return @name
    end

    UTF_8 = Encoding.new("UTF-8")
    ASCII_8BIT = Encoding.new("US-ASCII")
  end
end

class ExampleProcessor
  def self.validate(name, value)
    return !!(value =~ /^[\w ]+$/) if name == "query"
    return true
  end

  def self.transform(name, value)
    return value.gsub(/ /, "+") if name == "query"
    return value
  end

  def self.restore(name, value)
    return value.gsub(/\+/, " ") if name == "query"
    return value.tr("A-Za-z", "N-ZA-Mn-za-m") if name == "rot13"
    return value
  end

  def self.match(name)
    return ".*?" if name == "first"
    return ".*"
  end
end

class SlashlessProcessor
  def self.match(name)
    return "[^/\\n]*"
  end
end

class NoOpProcessor
  def self.transform(name, value)
    value
  end
end

describe Addressable::Template do
  it "should raise a TypeError for invalid patterns" do
    (lambda do
      Addressable::Template.new(42)
    end).should raise_error(TypeError, "Can't convert Fixnum into String.")
  end
end

describe Addressable::URI, "when parsed from '/'" do
  before do
    @uri = Addressable::URI.parse("/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/'" do
    @uri.extract_mapping("/").should == {}
  end
end

describe Addressable::URI, "when parsed from '/one/'" do
  before do
    @uri = Addressable::URI.parse("/one/")
  end

  it "should not match the pattern '/two/'" do
    @uri.extract_mapping("/two/").should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{number}/'" do
    @uri.extract_mapping("/{number}/").should == {"number" => "one"}
  end
end

describe Addressable::Template, "created with the pattern '/{number}/'" do
  before do
    @template = Addressable::Template.new("/{number}/")
  end

  it "should have the variables ['number']" do
    @template.variables.should == ["number"]
  end

  it "should not match the pattern '/'" do
    @template.match("/").should == nil
  end

  it "should match the pattern '/two/'" do
    @template.match("/two/").mapping.should == {"number" => "two"}
  end
end

describe Addressable::Template, "created with the pattern " +
    "'http://www.example.com/?{-join|&|query,number}'" do
  before do
    @template = Addressable::Template.new(
      "http://www.example.com/?{-join|&|query,number}"
    )
  end

  it "when inspected, should have the correct class name" do
    @template.inspect.should include("Addressable::Template")
  end

  it "when inspected, should have the correct object id" do
    @template.inspect.should include("%#0x" % @template.object_id)
  end

  it "should have the variables ['query', 'number']" do
    @template.variables.should == ["query", "number"]
  end

  it "should not match the pattern 'http://www.example.com/'" do
    @template.match("http://www.example.com/").should == nil
  end

  it "should match the pattern 'http://www.example.com/?'" do
    @template.match("http://www.example.com/?").mapping.should == {}
  end

  it "should match the pattern " +
      "'http://www.example.com/?query=mycelium'" do
    match = @template.match(
      "http://www.example.com/?query=mycelium"
    )
    match.variables.should == ["query", "number"]
    match.values.should == ["mycelium", nil]
    match.mapping.should == {"query" => "mycelium"}
    match.inspect.should =~ /MatchData/
  end

  it "should match the pattern " +
      "'http://www.example.com/?query=mycelium&number=100'" do
    @template.match(
      "http://www.example.com/?query=mycelium&number=100"
    ).mapping.should == {"query" => "mycelium", "number" => "100"}
  end
end

describe Addressable::URI, "when parsed from '/one/two/'" do
  before do
    @uri = Addressable::URI.parse("/one/two/")
  end

  it "should not match the pattern '/{number}/' " +
      "with the SlashlessProcessor" do
    @uri.extract_mapping("/{number}/", SlashlessProcessor).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{number}/' without a processor" do
    @uri.extract_mapping("/{number}/").should == {
      "number" => "one/two"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern '/{first}/{second}/' with the SlashlessProcessor" do
    @uri.extract_mapping("/{first}/{second}/", SlashlessProcessor).should == {
      "first" => "one",
      "second" => "two"
    }
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/search/an+example+search+query/'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/search/an+example+search+query/")
  end

  it "should have the correct mapping when extracting values using " +
      "the pattern 'http://example.com/search/{query}/' with the " +
      "ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/search/{query}/", ExampleProcessor
    ).should == {
      "query" => "an example search query"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/search/{-list|+|query}/'" do
    @uri.extract_mapping(
      "http://example.com/search/{-list|+|query}/"
    ).should == {
      "query" => ["an", "example", "search", "query"]
    }
  end

  it "should return nil when extracting values using " +
      "a non-matching pattern" do
    @uri.extract_mapping(
      "http://bogus.com/{thingy}/"
    ).should == nil
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/a/b/c/'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/a/b/c/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{second}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{first}/{second}/", ExampleProcessor
    ).should == {
      "first" => "a",
      "second" => "b/c"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{-list|/|second}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/{-list|/|second}/"
    ).should == {
      "first" => "a",
      "second" => ["b", "c"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/{-list|/|rot13}/' " +
      "with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{first}/{-list|/|rot13}/",
      ExampleProcessor
    ).should == {
      "first" => "a",
      "rot13" => ["o", "p"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-list|/|rot13}/' " +
      "with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-list|/|rot13}/",
      ExampleProcessor
    ).should == {
      "rot13" => ["n", "o", "p"]
    }
  end

  it "should not map to anything when extracting values " +
      "using the pattern " +
      "'http://example.com/{-list|/|rot13}/'" do
    @uri.extract_mapping("http://example.com/{-join|/|a,b,c}/").should == nil
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/?a=one&b=two&c=three'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?a=one&b=two&c=three")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/?{-join|&|a,b,c}'" do
    @uri.extract_mapping(
      "http://example.com/?{-join|&|a,b,c}"
    ).should == {
      "a" => "one",
      "b" => "two",
      "c" => "three"
    }
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/?rot13=frperg'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/?rot13=frperg")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/?{-join|&|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/?{-join|&|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => "secret"
    }
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/one/spacer/two/'" do
  before do
    @uri = Addressable::URI.parse("http://example.com/one/spacer/two/")
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer/{second}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer/{second}/"
    ).should == {
      "first" => "one",
      "second" => "two"
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|stuff}/"
    ).should == {
      "stuff" => ["one", "spacer", "two"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/o{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/o{-prefix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer{-prefix|/|stuff}/"
    ).should == {
      "first" => "one",
      "stuff" => ["two"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-prefix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{-prefix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|rot13}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|rot13}/",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-prefix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-prefix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb", ""]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-prefix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-prefix|/|rot13}",
      ExampleProcessor
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}"
    ).should == {
      "stuff" => ["one", "spacer", "two"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|stuff}o'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}o"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/o{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/o{-suffix|/|stuff}"
    ).should == {"stuff"=>["ne", "spacer", "two"]}
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{first}/spacer/{-suffix|/|stuff}'" do
    @uri.extract_mapping(
      "http://example.com/{first}/spacer/{-suffix|/|stuff}"
    ).should == {
      "first" => "one",
      "stuff" => ["two"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-suffix|/|stuff}/'" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|stuff}/"
    ).should == nil
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com/{-suffix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["bar", "fcnpre", "gjb"]
    }
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://example.com{-suffix|/|rot13}' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com{-suffix|/|rot13}",
      ExampleProcessor
    ).should == {
      "rot13" => ["", "bar", "fcnpre", "gjb"]
    }
  end

  it "should not match anything when extracting values " +
      "using the incorrect suffix pattern " +
      "'http://example.com/{-suffix|/|rot13}/' with the ExampleProcessor" do
    @uri.extract_mapping(
      "http://example.com/{-suffix|/|rot13}/",
      ExampleProcessor
    ).should == nil
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/?email=bob@sporkmonger.com'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/?email=bob@sporkmonger.com"
    )
  end

  it "should not match anything when extracting values " +
      "using the incorrect opt pattern " +
      "'http://example.com/?email={-opt|bogus@bogus.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bogus@bogus.com|test}"
    ).should == nil
  end

  it "should not match anything when extracting values " +
      "using the incorrect neg pattern " +
      "'http://example.com/?email={-neg|bogus@bogus.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bogus@bogus.com|test}"
    ).should == nil
  end

  it "should indicate a match when extracting values " +
      "using the opt pattern " +
      "'http://example.com/?email={-opt|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bob@sporkmonger.com|test}"
    ).should == {}
  end

  it "should indicate a match when extracting values " +
      "using the neg pattern " +
      "'http://example.com/?email={-neg|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bob@sporkmonger.com|test}"
    ).should == {}
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/?email='" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/?email="
    )
  end

  it "should indicate a match when extracting values " +
      "using the opt pattern " +
      "'http://example.com/?email={-opt|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-opt|bob@sporkmonger.com|test}"
    ).should == {}
  end

  it "should indicate a match when extracting values " +
      "using the neg pattern " +
      "'http://example.com/?email={-neg|bob@sporkmonger.com|test}'" do
    @uri.extract_mapping(
      "http://example.com/?email={-neg|bob@sporkmonger.com|test}"
    ).should == {}
  end
end

describe Addressable::URI, "when parsed from " +
    "'http://example.com/a/b/c/?one=1&two=2#foo'" do
  before do
    @uri = Addressable::URI.parse(
      "http://example.com/a/b/c/?one=1&two=2#foo"
    )
  end

  it "should have the correct mapping when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|one,two}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,two}\#{fragment}"
    ).should == {
      "host" => "example.com",
      "segments" => ["a", "b", "c"],
      "one" => "1",
      "two" => "2",
      "fragment" => "foo"
    }
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|one}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?{-join|&|bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|bogus}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?" +
      "{-join|&|one,bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,bogus}\#{fragment}"
    ).should == nil
  end

  it "should not match when extracting values " +
      "using the pattern " +
      "'http://{host}/{-suffix|/|segments}?" +
      "{-join|&|one,two,bogus}\#{fragment}'" do
    @uri.extract_mapping(
      "http://{host}/{-suffix|/|segments}?{-join|&|one,two,bogus}\#{fragment}"
    ).should == {
      "host" => "example.com",
      "segments" => ["a", "b", "c"],
      "one" => "1",
      "two" => "2",
      "fragment" => "foo"
    }
  end
end

describe Addressable::URI, "when given a pattern with bogus operators" do
  before do
    @uri = Addressable::URI.parse("http://example.com/a/b/c/")
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-bogus|/|a,b,c}/")
    end).should raise_error(
      Addressable::Template::InvalidTemplateOperatorError
    )
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-prefix|/|a,b,c}/")
    end).should raise_error(
      Addressable::Template::InvalidTemplateOperatorError
    )
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-suffix|/|a,b,c}/")
    end).should raise_error(
      Addressable::Template::InvalidTemplateOperatorError
    )
  end

  it "should raise an InvalidTemplateOperatorError" do
    (lambda do
      @uri.extract_mapping("http://example.com/{-list|/|a,b,c}/")
    end).should raise_error(
      Addressable::Template::InvalidTemplateOperatorError
    )
  end
end
