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

require "addressable/uri"
require "addressable/template"

describe Addressable::UnicodeNormalization do
  let(:limit) { Addressable::UnicodeNormalization::MAX_COMBINING_MARKS }

  def normalize(string, form = :nfc)
    Addressable::UnicodeNormalization.normalize(string, form)
  end

  it "normalizes text as String#unicode_normalize does" do
    expect(normalize("é")).to eq("é")
    expect(normalize("Ａ́", :nfkc)).to eq("Á")
    expect(normalize("각")).to eq("각")
  end

  it "normalizes a run of as many combining marks as the limit" do
    string = "a" + "̣́" * (limit / 2)
    expect(normalize(string)).to eq(string.unicode_normalize(:nfc))
    expect(normalize(string)).not_to eq(string)
  end

  it "leaves a longer run of combining marks as it is" do
    # This isn't NFC: the marks keep their order and aren't composed with
    # the character before them, so two runs that differ only in the order
    # of their marks don't normalize to the same string.
    marks = "̣́" * limit
    expect(normalize("a" + marks)).to eq("a" + marks)
  end

  it "normalizes the text around a longer run of combining marks" do
    marks = "́" * (limit + 1)
    expect(normalize("é a#{marks} é")).to eq(
      "é a#{marks} é"
    )
  end

  it "counts U+FF9E and U+FF9F, which NFKC maps to combining marks" do
    marks = "ﾞ" * (limit + 1)
    expect(normalize("カ#{marks}", :nfkc)).to eq("カ#{marks}")
    expect(normalize("ｶﾞ", :nfkc)).to eq("ガ")
  end

  it "gives the same result when normalizing again" do
    string = "é" + "̈́" * limit + "a" + "́" * (limit + 1)
    once = normalize(string)
    expect(normalize(once)).to eq(once)
  end

  it "raises for a string that isn't valid UTF-8, as String does" do
    expect { normalize("\xFF") }.to raise_error(ArgumentError)
  end

  context "with thousands of combining marks" do
    # On a Ruby whose String#unicode_normalize takes quadratic time, such as
    # 3.2, each of these takes over a minute without the limit.
    let(:marks) { "̣́" * 20_000 }
    let(:encoded_marks) { "%CC%81%CC%A3" * 20_000 }

    def seconds
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    it "normalizes a URI in linear time" do
      uri = Addressable::URI.parse("http://example.com/a#{marks}?a#{marks}")
      expect(seconds { uri.normalize.to_s }).to be < 10
    end

    it "normalizes a URI with pct-encoded marks in linear time" do
      uri = Addressable::URI.parse("http://example.com/a#{encoded_marks}")
      expect(seconds { uri.normalize.to_s }).to be < 10
      expect(uri.normalize.path).to eq("/a#{encoded_marks}")
    end

    it "compares URIs in linear time" do
      uri = Addressable::URI.parse("http://example.com/a#{encoded_marks}")
      other = Addressable::URI.parse("http://example.com/")
      expect(seconds { uri == other }).to be < 10
    end

    it "encodes a URI in linear time" do
      expect(
        seconds do
          Addressable::URI.normalized_encode("http://example.com/a#{marks}")
        end
      ).to be < 10
    end

    it "converts a host to ASCII in linear time" do
      expect(
        seconds do
          begin
            Addressable::IDNA.to_ascii("a#{marks}.example.com")
          rescue Addressable::IDNA::PunycodeBigOutput
          end
        end
      ).to be < 10
    end

    it "matches and expands a template in linear time" do
      template = Addressable::Template.new("http://example.com/{a}")
      expect(
        seconds { template.match("http://example.com/a#{encoded_marks}") }
      ).to be < 10
      expect(seconds { template.expand("a" => "a#{marks}") }).to be < 10
    end
  end
end
