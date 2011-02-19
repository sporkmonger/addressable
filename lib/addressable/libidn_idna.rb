module Addressable
  module IDNA
    def self.punycode_encode(value)
      IDN::Punycode.encode(value)
    end

     def self.punycode_decode(value)
       IDN::Punycode.decode(value)
     end

    def self.unicode_normalize_kc(value)
      IDN::Stringprep.nfkc_normalize(value)
    end

    def self.to_ascii(value)
      IDN::Idna.toASCII(value)
    end

    def self.to_unicode(value)
      IDN::Idna.toUnicode(value)
    end
  end
end
