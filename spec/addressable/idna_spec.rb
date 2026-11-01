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

# Have to use RubyGems to load the idn gem.
require "rubygems"

require "addressable/idna"
require "addressable/uri"

shared_examples_for "converting from unicode to ASCII" do
  it "should convert 'www.google.com' correctly" do
    expect(Addressable::IDNA.to_ascii("www.google.com")).to eq("www.google.com")
  end

  long = 'AcinusFallumTrompetumNullunCreditumVisumEstAtCuadLongumEtCefallum.com'
  it "should convert '#{long}' correctly" do
    expect(Addressable::IDNA.to_ascii(long)).to eq(long)
  end

  it "should convert 'www.詹姆斯.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "www.詹姆斯.com"
    )).to eq("www.xn--8ws00zhy3a.com")
  end

  it "also accepts unicode strings encoded as ascii-8bit" do
    expect(Addressable::IDNA.to_ascii(
      "www.詹姆斯.com".b
    )).to eq("www.xn--8ws00zhy3a.com")
  end

  it "should convert 'www.Iñtërnâtiônàlizætiøn.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "www.I\xC3\xB1t\xC3\xABrn\xC3\xA2ti\xC3\xB4" +
      "n\xC3\xA0liz\xC3\xA6ti\xC3\xB8n.com"
    )).to eq("www.xn--itrntinliztin-vdb0a5exd8ewcye.com")
  end

  it "should convert 'www.Iñtërnâtiônàlizætiøn.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "www.In\xCC\x83te\xCC\x88rna\xCC\x82tio\xCC\x82n" +
      "a\xCC\x80liz\xC3\xA6ti\xC3\xB8n.com"
    )).to eq("www.xn--itrntinliztin-vdb0a5exd8ewcye.com")
  end

  it "should convert " +
      "'www.ほんとうにながいわけのわからないどめいんめいのらべるまだながくしないとたりない.w3.mag.keio.ac.jp' " +
      "correctly" do
    expect(Addressable::IDNA.to_ascii(
      "www.\343\201\273\343\202\223\343\201\250\343\201\206\343\201\253\343" +
      "\201\252\343\201\214\343\201\204\343\202\217\343\201\221\343\201\256" +
      "\343\202\217\343\201\213\343\202\211\343\201\252\343\201\204\343\201" +
      "\251\343\202\201\343\201\204\343\202\223\343\202\201\343\201\204\343" +
      "\201\256\343\202\211\343\201\271\343\202\213\343\201\276\343\201\240" +
      "\343\201\252\343\201\214\343\201\217\343\201\227\343\201\252\343\201" +
      "\204\343\201\250\343\201\237\343\202\212\343\201\252\343\201\204." +
      "w3.mag.keio.ac.jp"
    )).to eq(
      "www.xn--n8jaaaaai5bhf7as8fsfk3jnknefdde3" +
      "fg11amb5gzdb4wi9bya3kc6lra.w3.mag.keio.ac.jp"
    )
  end

  it "should convert " +
      "'www.ほんとうにながいわけのわからないどめいんめいのらべるまだながくしないとたりない.w3.mag.keio.ac.jp' " +
      "correctly" do
    expect(Addressable::IDNA.to_ascii(
      "www.\343\201\273\343\202\223\343\201\250\343\201\206\343\201\253\343" +
      "\201\252\343\201\213\343\202\231\343\201\204\343\202\217\343\201\221" +
      "\343\201\256\343\202\217\343\201\213\343\202\211\343\201\252\343\201" +
      "\204\343\201\250\343\202\231\343\202\201\343\201\204\343\202\223\343" +
      "\202\201\343\201\204\343\201\256\343\202\211\343\201\270\343\202\231" +
      "\343\202\213\343\201\276\343\201\237\343\202\231\343\201\252\343\201" +
      "\213\343\202\231\343\201\217\343\201\227\343\201\252\343\201\204\343" +
      "\201\250\343\201\237\343\202\212\343\201\252\343\201\204." +
      "w3.mag.keio.ac.jp"
    )).to eq(
      "www.xn--n8jaaaaai5bhf7as8fsfk3jnknefdde3" +
      "fg11amb5gzdb4wi9bya3kc6lra.w3.mag.keio.ac.jp"
    )
  end

  it "should convert '点心和烤鸭.w3.mag.keio.ac.jp' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "点心和烤鸭.w3.mag.keio.ac.jp"
    )).to eq("xn--0trv4xfvn8el34t.w3.mag.keio.ac.jp")
  end

  it "should convert '가각갂갃간갅갆갇갈갉힢힣.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "가각갂갃간갅갆갇갈갉힢힣.com"
    )).to eq("xn--o39acdefghijk5883jma.com")
  end

  it "should convert " +
      "'\347\242\274\346\250\231\346\272\226\350" +
      "\220\254\345\234\213\347\242\274.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\347\242\274\346\250\231\346\272\226\350" +
      "\220\254\345\234\213\347\242\274.com"
    )).to eq("xn--9cs565brid46mda086o.com")
  end

  it "should convert 'ﾘ宠퐱〹.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\357\276\230\345\256\240\355\220\261\343\200\271.com"
    )).to eq("xn--eek174hoxfpr4k.com")
  end

  it "should convert 'リ宠퐱卄.com' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\343\203\252\345\256\240\355\220\261\345\215\204.com"
    )).to eq("xn--eek174hoxfpr4k.com")
  end

  it "should convert 'ᆵ' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\341\206\265"
    )).to eq("xn--4ud")
  end

  it "should convert 'ﾯ' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\357\276\257"
    )).to eq("xn--4ud")
  end

  it "should convert '🌹🌹🌹.ws' correctly" do
    expect(Addressable::IDNA.to_ascii(
      "\360\237\214\271\360\237\214\271\360\237\214\271.ws"
    )).to eq("xn--2h8haa.ws")
  end

  it "should handle two adjacent '.'s correctly" do
    expect(Addressable::IDNA.to_ascii(
      "example..host"
    )).to eq("example..host")
  end

  {
    "bücher.example." => "xn--bcher-kva.example.",
    "bücher.example.." => "xn--bcher-kva.example..",
    "ü." => "xn--tda.",
    ".bücher" => ".xn--bcher-kva",
    "bücher..example" => "xn--bcher-kva..example",
    "." => ".",
    ".." => "..",
    "" => ""
  }.each do |unicode, ascii|
    it "should keep the empty labels in #{unicode.inspect}" do
      expect(Addressable::IDNA.to_ascii(unicode)).to eq(ascii)
    end
  end
end

shared_examples_for "converting from ASCII to unicode" do
  long = 'AcinusFallumTrompetumNullunCreditumVisumEstAtCuadLongumEtCefallum.com'
  it "should convert '#{long}' correctly" do
    expect(Addressable::IDNA.to_unicode(long)).to eq(long)
  end

  it "should return the identity conversion when punycode decode fails" do
    expect(Addressable::IDNA.to_unicode("xn--zckp1cyg1.sblo.jp")).to eq(
      "xn--zckp1cyg1.sblo.jp")
  end

  it "should return the identity conversion when the ACE prefix has no suffix" do
    expect(Addressable::IDNA.to_unicode("xn--...-")).to eq("xn--...-")
  end

  it "should return the identity conversion when a Punycode digit isn't alphanumeric" do
    labels = %w(
      xn--: xn--bcher-k:a xn--bcher-k_a xn--rp3= xn--440gp_b xn--swi0s8>1l
      xn--9xiZ<b9 xn--bi1rwuP_
    )
    labels.each do |label|
      expect(Addressable::IDNA.to_unicode(label)).to eq(label)
      expect(Addressable::IDNA.to_unicode("#{label}.example")).to eq(
        "#{label}.example"
      )
    end
  end

  it "should display a URI whose host has a Punycode digit that isn't alphanumeric" do
    uri = Addressable::URI.parse("http://xn--rp3=.example/")
    expect(uri.display_uri.to_s).to eq("http://xn--rp3=.example/")
  end

  it "should convert 'www.google.com' correctly" do
    expect(Addressable::IDNA.to_unicode("www.google.com")).to eq(
      "www.google.com")
  end

  it "should convert 'www.詹姆斯.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "www.xn--8ws00zhy3a.com"
    )).to eq("www.詹姆斯.com")
  end

  it "should convert '詹姆斯.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--8ws00zhy3a.com"
    )).to eq("詹姆斯.com")
  end

  it "should convert 'www.iñtërnâtiônàlizætiøn.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "www.xn--itrntinliztin-vdb0a5exd8ewcye.com"
    )).to eq("www.iñtërnâtiônàlizætiøn.com")
  end

  it "should convert 'iñtërnâtiônàlizætiøn.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--itrntinliztin-vdb0a5exd8ewcye.com"
    )).to eq("iñtërnâtiônàlizætiøn.com")
  end

  it "should convert " +
      "'www.ほんとうにながいわけのわからないどめいんめいのらべるまだながくしないとたりない.w3.mag.keio.ac.jp' " +
      "correctly" do
    expect(Addressable::IDNA.to_unicode(
      "www.xn--n8jaaaaai5bhf7as8fsfk3jnknefdde3" +
      "fg11amb5gzdb4wi9bya3kc6lra.w3.mag.keio.ac.jp"
    )).to eq(
      "www.ほんとうにながいわけのわからないどめいんめいのらべるまだながくしないとたりない.w3.mag.keio.ac.jp"
    )
  end

  it "should convert '点心和烤鸭.w3.mag.keio.ac.jp' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--0trv4xfvn8el34t.w3.mag.keio.ac.jp"
    )).to eq("点心和烤鸭.w3.mag.keio.ac.jp")
  end

  it "should convert '가각갂갃간갅갆갇갈갉힢힣.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--o39acdefghijk5883jma.com"
    )).to eq("가각갂갃간갅갆갇갈갉힢힣.com")
  end

  it "should convert " +
      "'\347\242\274\346\250\231\346\272\226\350" +
      "\220\254\345\234\213\347\242\274.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--9cs565brid46mda086o.com"
    )).to eq(
      "\347\242\274\346\250\231\346\272\226\350" +
      "\220\254\345\234\213\347\242\274.com"
    )
  end

  it "should convert 'リ宠퐱卄.com' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--eek174hoxfpr4k.com"
    )).to eq("\343\203\252\345\256\240\355\220\261\345\215\204.com")
  end

  it "should convert 'ﾯ' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--4ud"
    )).to eq("\341\206\265")
  end

  it "should convert '🌹🌹🌹.ws' correctly" do
    expect(Addressable::IDNA.to_unicode(
      "xn--2h8haa.ws"
    )).to eq("\360\237\214\271\360\237\214\271\360\237\214\271.ws")
  end

  it "should handle two adjacent '.'s correctly" do
    expect(Addressable::IDNA.to_unicode(
      "example..host"
    )).to eq("example..host")
  end

  # toUnicode never fails (Section 4.2 of RFC 3490), so a label that can't be
  # decoded is returned unchanged.
  {
    "a label too long to decode" => "xn--" + ("a" * 600),
    "a label that overflows the decoder" => "xn--" + ("9" * 20),
    "a label that decodes past U+10FFFF" => "xn--99999999999a"
  }.each do |description, label|
    it "should return the identity conversion for #{description}" do
      expect(Addressable::IDNA.to_unicode(label)).to eq(label)
      expect(Addressable::IDNA.to_unicode("www.#{label}.com")).to eq(
        "www.#{label}.com"
      )
    end
  end

  it "should convert the other labels when one label can't be decoded" do
    label = "xn--" + ("9" * 20)
    expect(Addressable::IDNA.to_unicode("xn--bcher-kva.#{label}.com")).to eq(
      "b\303\274cher.#{label}.com"
    )
  end

  # An A-label that decodes to only ASCII characters isn't valid, so it's
  # returned unchanged.
  it "leaves malformed A-label in place on to_unicode (toUnicode never-fails)" do
    expect(
      Addressable::IDNA.to_unicode("xn--google-.example.org")
    ).to eq("xn--google-.example.org")
  end

  it "leaves bare malformed A-label in place on to_unicode" do
    expect(
      Addressable::IDNA.to_unicode("xn--example-")
    ).to eq("xn--example-")
  end

  # A label that doesn't convert back to itself with toASCII isn't a valid
  # A-label either (Section 4.2 of RFC 3490, steps 6 and 7), so it's returned
  # unchanged.
  {
    "a label that decodes to ASCII after its basic code points" =>
      "xn--mnchen-3ya-",
    "a label with a decomposed character" => "xn--munchen-gie",
    "a label with a compatibility character" => "xn--le-1b1n",
    "a label with a fullwidth character" => "xn--oo-yka3051x",
    "a label with a fullwidth full stop" => "xn--paypalcom-b854c",
    "a label with a halfwidth ideographic full stop" => "xn--paypalcom-0w64c",
    "a label with an uppercase non-ASCII character" => "xn--Mnchen-psa",
    "a label that decodes to surrogate code points" => "xn--8b9bscx9u"
  }.each do |description, label|
    it "should return the identity conversion for #{description}" do
      expect(Addressable::IDNA.to_unicode(label)).to eq(label)
      expect(Addressable::IDNA.to_unicode("www.#{label}.com")).to eq(
        "www.#{label}.com"
      )
    end
  end

  it "should convert a label with uppercase ASCII letters" do
    expect(Addressable::IDNA.to_unicode("xn--Mnchen-3ya.de")).to eq(
      "M\303\274nchen.de"
    )
    expect(Addressable::IDNA.to_unicode("xn--MNCHEN-3YA.de")).to eq(
      "M\303\274NCHEN.de"
    )
  end

  # Nameprep doesn't allow these characters in a label (tables C.1.2 to C.9
  # of RFC 3454) or maps them to nothing (table B.1), so a label that decodes
  # to one of them is returned unchanged. Each label is "mün<character>chen".
  {
    "a right-to-left override (U+202E)" => "xn--mnchen-3ya3005d",
    "a left-to-right mark (U+200E)" => "xn--mnchen-3ya7474d",
    "a right-to-left mark (U+200F)" => "xn--mnchen-3ya5574d",
    "a left-to-right embedding (U+202A)" => "xn--mnchen-3ya1794d",
    "a deprecated format character (U+206A)" => "xn--mnchen-3ya3845d",
    "a tag character (U+E0041)" => "xn--mnchen-3ya156944e",
    "a language tag (U+E0001)" => "xn--mnchen-3ya931944e",
    "a C1 control character (U+0085)" => "xn--mnchen-cba46g",
    "a line separator (U+2028)" => "xn--mnchen-3ya5594d",
    "an invisible function application (U+2061)" => "xn--mnchen-3ya1145d",
    "an interlinear annotation anchor (U+FFF9)" => "xn--mnchen-3ya13333c",
    "a musical format character (U+1D173)" => "xn--mnchen-3ya93326g",
    "an Arabic end of ayah (U+06DD)" => "xn--mnchen-3ya551j",
    "an ogham space mark (U+1680)" => "xn--mnchen-3ya9715b",
    "a private use character (U+E000)" => "xn--mnchen-3ya15876b",
    "a supplementary private use character (U+F0000)" =>
      "xn--mnchen-3ya914379e",
    "a noncharacter (U+FDD0)" => "xn--mnchen-3ya70982c",
    "a supplementary noncharacter (U+10FFFF)" => "xn--mnchen-3ya789120g",
    "a replacement character (U+FFFD)" => "xn--mnchen-3ya36333c",
    "an ideographic description character (U+2FF0)" => "xn--mnchen-3ya5727g",
    "a soft hyphen (U+00AD)" => "xn--mnchen-cja44d",
    "a zero width space (U+200B)" => "xn--mnchen-3ya3274d",
    "a zero width joiner (U+200D)" => "xn--mnchen-3ya9374d",
    "a variation selector (U+FE0F)" => "xn--mnchen-3ya11492c",
    "a zero width no-break space (U+FEFF)" => "xn--mnchen-3ya13313c",
    "a combining grapheme joiner (U+034F)" => "xn--mnchen-3ya578b",
    "a Mongolian free variation selector (U+180B)" => "xn--mnchen-3ya9338b",
    "a Mongolian todo soft hyphen (U+1806)" => "xn--mnchen-3ya9928b"
  }.each do |description, label|
    it "should return the identity conversion for a label with " +
        description do
      expect(Addressable::IDNA.to_unicode(label)).to eq(label)
      expect(Addressable::IDNA.to_unicode("www.#{label}.com")).to eq(
        "www.#{label}.com"
      )
    end
  end

  # Controls, format characters and default ignorable code points change how
  # a label displays, including those added to Unicode after the version
  # nameprep is based on, so a label that decodes to one of them is returned
  # unchanged too. Each label is "mün<character>chen".
  {
    "an Arabic letter mark (U+061C)" => "xn--mnchen-3ya116h",
    "a left-to-right isolate (U+2066)" => "xn--mnchen-3ya1545d",
    "a right-to-left isolate (U+2067)" => "xn--mnchen-3ya9545d",
    "a first strong isolate (U+2068)" => "xn--mnchen-3ya7645d",
    "a pop directional isolate (U+2069)" => "xn--mnchen-3ya5745d",
    "a control character (U+0001)" => "xn--mn\u0001chen-n2a",
    "a tab (U+0009)" => "xn--mn\tchen-n2a",
    "a line feed (U+000A)" => "xn--mn\nchen-n2a",
    "a carriage return (U+000D)" => "xn--mn\rchen-n2a",
    "a delete character (U+007F)" => "xn--mn\u007Fchen-n2a",
    "an invisible plus (U+2064)" => "xn--mnchen-3ya5345d",
    "an Arabic number sign (U+0600)" => "xn--mnchen-3ya783h",
    "a Hangul filler (U+115F)" => "xn--mnchen-3ya5764a",
    "a shorthand format control (U+1BCA0)" => "xn--mnchen-3ya19691g",
    "a reserved default ignorable code point (U+E0002)" =>
      "xn--mnchen-3ya741944e"
  }.each do |description, label|
    it "should return the identity conversion for a label with " +
        description do
      expect(Addressable::IDNA.to_unicode(label)).to eq(label)
      expect(Addressable::IDNA.to_unicode("www.#{label}.com")).to eq(
        "www.#{label}.com"
      )
    end
  end

  {
    "xn--mgbh0fb" => "\331\205\330\253\330\247\331\204",
    "xn--4dbrk0ce" => "\327\231\327\251\327\250\327\220\327\234",
    "xn--n3h" => "\342\230\203"
  }.each do |label, decoded|
    it "should convert '#{label}' correctly" do
      expect(Addressable::IDNA.to_unicode("#{label}.example")).to eq(
        "#{decoded}.example"
      )
    end
  end

  {
    "xn--bcher-kva.example." => "bücher.example.",
    "xn--bcher-kva.example.." => "bücher.example..",
    "xn--tda." => "ü.",
    ".xn--tda" => ".ü",
    "xn--tda..xn--tda" => "ü..ü",
    "example.com." => "example.com.",
    "." => ".",
    ".." => "..",
    "" => ""
  }.each do |ascii, unicode|
    it "should keep the empty labels in #{ascii.inspect}" do
      expect(Addressable::IDNA.to_unicode(ascii)).to eq(unicode)
    end
  end
end

# Every Unicode scalar value, U+0000 to U+10FFFF without the surrogates.
ALL_CODE_POINTS = ((0..0xD7FF).to_a + (0xE000..0x10FFFF).to_a).
  pack("U*").freeze

shared_examples_for "matching display-changing characters" do
  it "should match exactly the controls, format characters and default " +
      "ignorable code points" do
    expected = ALL_CODE_POINTS.scan(
      /\p{Cc}|\p{Cf}|\p{Default_Ignorable_Code_Point}/
    )
    expect(ALL_CODE_POINTS.scan(Addressable::IDNA::DISPLAY_CHANGING)).to eq(
      expected
    )
  end
end

describe Addressable::IDNA, "when using the pure-Ruby implementation" do
  before do
    Addressable.send(:remove_const, :IDNA)
    load "addressable/idna/pure.rb"
  end

  it_should_behave_like "converting from unicode to ASCII"
  it_should_behave_like "converting from ASCII to unicode"
  it_should_behave_like "matching display-changing characters"

  it "should prohibit exactly the code points in the nameprep tables" do
    tables = [
      # RFC 3454 Table C.1.2, non-ASCII space characters
      [0x00A0, 0x1680, 0x2000..0x200B, 0x202F, 0x205F, 0x3000],
      # Table C.2.2, non-ASCII control characters
      [0x0080..0x009F, 0x06DD, 0x070F, 0x180E, 0x200C, 0x200D, 0x2028,
       0x2029, 0x2060..0x2063, 0x206A..0x206F, 0xFEFF, 0xFFF9..0xFFFC,
       0x1D173..0x1D17A],
      # Table C.3, private use
      [0xE000..0xF8FF, 0xF0000..0xFFFFD, 0x100000..0x10FFFD],
      # Table C.4, non-character code points
      [0xFDD0..0xFDEF] + (0..16).map do |plane|
        (plane * 0x10000 + 0xFFFE)..(plane * 0x10000 + 0xFFFF)
      end,
      # Table C.6, inappropriate for plain text
      [0xFFF9..0xFFFD],
      # Table C.7, inappropriate for canonical representation
      [0x2FF0..0x2FFB],
      # Table C.8, change display properties or are deprecated
      [0x0340, 0x0341, 0x200E, 0x200F, 0x202A..0x202E, 0x206A..0x206F],
      # Table C.9, tagging characters
      [0xE0001, 0xE0020..0xE007F],
      # Table B.1, commonly mapped to nothing
      [0x00AD, 0x034F, 0x1806, 0x180B..0x180D, 0x200B..0x200D, 0x2060,
       0xFE00..0xFE0F, 0xFEFF]
    ]
    expected = tables.flatten.flat_map { |entry| Array(entry) }.uniq.sort
    prohibited = ALL_CODE_POINTS.scan(
      Addressable::IDNA::NAMEPREP_PROHIBITED
    ).map(&:ord)
    expect(prohibited).to eq(expected)
  end

  it "should decode only letters and digits as Punycode digits" do
    digits = (0..127).map do |codepoint|
      Addressable::IDNA.send(:punycode_decode_digit, codepoint)
    end
    expected = (0..127).map do |codepoint|
      case codepoint.chr
      when "a".."z" then codepoint - 97
      when "A".."Z" then codepoint - 65
      when "0".."9" then codepoint - 22
      else Addressable::IDNA::PUNYCODE_BASE
      end
    end
    expect(digits).to eq(expected)
  end

  it "should encode the RFC 3492 sample strings" do
    samples = {
      [0x4ED6, 0x4EEC, 0x4E3A, 0x4EC0, 0x4E48, 0x4E0D, 0x8BF4, 0x4E2D,
       0x6587] => "ihqwcrb4cv8a8dqg056pqjye",
      [0x4ED6, 0x5011, 0x7232, 0x4EC0, 0x9EBD, 0x4E0D, 0x8AAA, 0x4E2D,
       0x6587] => "ihqwctvzc91f659drss3x8bo0yb",
      [0x0033, 0x5E74, 0x0042, 0x7D44, 0x91D1, 0x516B, 0x5148,
       0x751F] => "3B-ww4c5e180e575a65lsy2b",
      [0x305D, 0x306E, 0x30B9, 0x30D4, 0x30FC, 0x30C9,
       0x3067] => "d9juau41awczczp",
      "-> $1.00 <-".unpack("U*") => "-> $1.00 <--"
    }
    samples.each do |code_points, punycode|
      unicode = code_points.pack("U*")
      expect(Addressable::IDNA.send(:punycode_encode, unicode)).to eq(punycode)
      expect(Addressable::IDNA.send(:punycode_decode, punycode)).to eq(unicode)
    end
  end

  it "should encode an empty string as an empty string" do
    expect(Addressable::IDNA.send(:punycode_encode, "")).to eq("")
  end

  it "should encode up to 256 characters of Punycode" do
    expect(Addressable::IDNA.send(:punycode_encode, "a" * 255)).to eq(
      "a" * 255 + "-"
    )
    expect(
      Addressable::IDNA.send(:punycode_encode, "a" * 252 + "é").size
    ).to eq(256)
    ["a" * 256, "a" * 253 + "é", "é" * 300].each do |unicode|
      expect {
        Addressable::IDNA.send(:punycode_encode, unicode)
      }.to raise_error(Addressable::IDNA::PunycodeBigOutput)
    end
  end

  it "should encode the longest labels in any order" do
    # 139 consecutive code points is the most that fit in 256 characters.
    code_points = (0x4E00...0x4E00 + 139).to_a
    random = Random.new(139)
    orders = [code_points, code_points.reverse,
      code_points.shuffle(random: random),
      ("a".ord..."a".ord + 26).to_a * 4 + code_points.first(40)]
    orders.each do |order|
      unicode = order.pack("U*")
      punycode = Addressable::IDNA.send(:punycode_encode, unicode)
      expect(punycode.size).to be <= 256
      expect(Addressable::IDNA.send(:punycode_decode, punycode)).to eq(unicode)
    end
    expect {
      Addressable::IDNA.send(
        :punycode_encode, (0x4E00...0x4E00 + 140).to_a.pack("U*")
      )
    }.to raise_error(Addressable::IDNA::PunycodeBigOutput)
  end

  it "should decode whatever it encodes" do
    random = Random.new(4471)
    ranges = [0x20..0x7E, 0x80..0x2FF, 0x370..0x3FF, 0x4E00..0x9FFF,
      0xAC00..0xD7A3, 0x10000..0x1FFFF]
    failures = []
    2000.times do
      unicode = Array.new(random.rand(70)) do
        range = ranges.sample(random: random)
        random.rand(range)
      end.pack("U*")
      begin
        punycode = Addressable::IDNA.send(:punycode_encode, unicode)
      rescue Addressable::IDNA::PunycodeBigOutput
        next
      end
      decoded = Addressable::IDNA.send(:punycode_decode, punycode)
      failures << [unicode, punycode] if decoded != unicode
    end
    expect(failures.first(5)).to eq([])
  end

  it "should reject a delimiter as the first Punycode digit" do
    expect {
      Addressable::IDNA.send(:punycode_decode, "-kva")
    }.to raise_error(Addressable::IDNA::PunycodeBadInput)
  end

  it "should return any label with a Punycode digit that isn't alphanumeric" do
    random = Random.new(614)
    ascii = (0..127).map(&:chr) - [".", "-"]
    alphanumeric = [*"a".."z", *"0".."9"]
    failures = []
    5000.times do
      digits = Array.new(1 + random.rand(12)) do
        random.rand < 0.8 ? alphanumeric.sample(random: random) :
          ascii.sample(random: random)
      end.join
      next if digits =~ /\A[a-zA-Z0-9]*\z/
      label = "xn--#{digits}"
      result = (Addressable::IDNA.to_unicode(label) rescue $!.class)
      failures << [label, result] if result != label
    end
    expect(failures.first(5)).to eq([])
  end

  begin
    require "fiber"

    it "should not blow up inside fibers" do
      f = Fiber.new do
        Addressable.send(:remove_const, :IDNA)
        load "addressable/idna/pure.rb"
      end
      f.resume
    end
  rescue LoadError
    # Fibers aren't supported in this version of Ruby, skip this test.
    warn('Fibers unsupported.')
  end
end

begin
  require "idn"

  describe Addressable::IDNA, "when using the native-code implementation" do
    before do
      Addressable.send(:remove_const, :IDNA)
      load "addressable/idna/native.rb"
    end

    it_should_behave_like "converting from unicode to ASCII"
    it_should_behave_like "converting from ASCII to unicode"
    it_should_behave_like "matching display-changing characters"
  end
rescue LoadError => error
  raise error if ENV["CI"] && TestHelper.native_supported?

  # Cannot test the native implementation without libidn support.
  warn('Could not load native IDN implementation.')
end
