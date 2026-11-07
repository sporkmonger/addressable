# frozen_string_literal: true
require "spec_helper"
require "addressable/template"

describe Addressable::Template, "matching non-ASCII text in either form" do
  def extract(pattern, uri)
    Addressable::Template.new(pattern).extract(uri)
  end

  {
    ["/café/{var}", "/caf%C3%A9/v"] => {"var" => "v"},
    ["/café/{var}", "/caf%c3%a9/v"] => {"var" => "v"},
    ["/café/{var}", "/café/v"] => {"var" => "v"},
    ["/caf%C3%A9/{var}", "/café/v"] => {"var" => "v"},
    ["/caf%c3%a9/{var}", "/café/v"] => {"var" => "v"},
    ["/caf%C3%A9/{var}", "/caf%C3%A9/v"] => {"var" => "v"},
    ["/caf%C3%A9/{var}", "/caf%c3%a9/v"] => {"var" => "v"},
    ["/{var}", "/café"] => {"var" => "café"},
    ["/{var}", "/caf%C3%A9"] => {"var" => "café"},
    ["/x{+var}", "/xcafé/b"] => {"var" => "café/b"},
    ["/x{#var}", "/x#café"] => {"var" => "café"},
    ["/x{/var}", "/x/café"] => {"var" => "café"},
    ["/x{.var}", "/x.café"] => {"var" => "café"},
    ["/x{;var}", "/x;var=café"] => {"var" => "café"},
    ["/x{?var}", "/x?var=café"] => {"var" => "café"},
    ["/x{?a,b}", "/x?a=é&b=€"] => {"a" => "é", "b" => "€"},
    ["/x{?a*}", "/x?k=é"] => {"a" => {"k" => "é"}},
    ["/{a}/é/{b}", "/1/é/2"] => {"a" => "1", "b" => "2"},
    ["/{a}é{b}", "/1é2"] => {"a" => "1", "b" => "2"},
    ["/{a}{b}", "/é"] => {"a" => nil, "b" => "é"},
    ["/\u{1D11E}/{var}", "/%F0%9D%84%9E/v"] => {"var" => "v"},
    ["/%F0%9D%84%9E/{var}", "/\u{1D11E}/v"] => {"var" => "v"}
  }.each do |(pattern, uri), mapping|
    it "extracts #{mapping} from #{uri} with #{pattern}" do
      expect(extract(pattern, uri)).to eq(mapping)
    end
  end

  it "doesn't match the same character in another form of the text" do
    expect(extract("/café/{var}", "/cafè/v")).to eq(nil)
    expect(extract("/caf%C3%A9/{var}", "/caf%C3%A8/v")).to eq(nil)
  end

  it "keeps reserved triplets distinct from the characters they encode" do
    expect(extract("/a%2Fb/{var}", "/a/b/v")).to eq(nil)
    expect(extract("/a/b/{var}", "/a%2Fb/v")).to eq(nil)
    expect(extract("/a%20b/{var}", "/a%20b/v")).to eq("var" => "v")
    expect(extract("/{var}", "/a/b")).to eq(nil)
  end

  it "keeps an invalid UTF-8 triplet as it is" do
    expect(extract("/%FF/{var}", "/%FF/v")).to eq("var" => "v")
    expect(extract("/%FF/{var}", "/%ff/v")).to eq("var" => "v")
  end

  it "keeps the given URI in the match data" do
    match = Addressable::Template.new("/{var}").match("/café")
    expect(match.uri.to_s).to eq("/café")
  end

  it "matches a URI that isn't UTF-8" do
    uri = "/caf\xC3\xA9/v".dup.force_encoding("BINARY")
    expect { extract("/café/{var}", uri) }.not_to raise_error
  end

  context "with a processor" do
    let(:processor) do
      Class.new do
        def self.match(name)
          name == "var" ? "café" : nil
        end
      end
    end

    it "gives the processor's pattern the URI as written" do
      template = Addressable::Template.new("/{var}")
      expect(template.extract("/café", processor)).to eq("var" => "café")
    end
  end

  it "stays linear on long non-ASCII text" do
    text = "é" * 50_000 + "!"
    {
      "/{a}/{b}" => "/", "/{a}{b}" => "/", "/{+a}{b}" => "/",
      "/{#a}{b}" => "/#", "/{.a}{.b}" => "/", "/{a,b}" => "/",
      "{/a*}{/b*}" => "/", "/{a*}{b*}{c*}" => "/", "{?a*,b*}" => "/",
      "/{a}-{b}-{c}" => "/", "{;a,b}" => ";a=", "{;a,b,c}" => ";a="
    }.each do |pattern, prefix|
      template = Addressable::Template.new(pattern)
      uri = prefix + text
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      template.extract(uri)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      expect([pattern, elapsed < 5]).to eq([pattern, true])
    end
  end
end
