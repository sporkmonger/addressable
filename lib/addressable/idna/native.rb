# frozen_string_literal: true

#--
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
#++


require "idn"

module Addressable
  module IDNA
    def self.punycode_encode(value)
      IDN::Punycode.encode(without_nul(value.to_s))
    end

    def self.punycode_decode(value)
      IDN::Punycode.decode(without_nul(value.to_s))
    end

    # libidn reads a NUL as the end of the string and would drop the rest.
    def self.without_nul(value)
      if value.include?("\0")
        raise IDN::Punycode::PunycodeError, "Invalid input: NUL"
      end
      value
    end
    private_class_method :without_nul

    class << self
      # @deprecated Use {String#unicode_normalize(:nfkc)} instead
      def unicode_normalize_kc(value)
        value.to_s.unicode_normalize(:nfkc)
      end

      extend Gem::Deprecate
      deprecate :unicode_normalize_kc, "String#unicode_normalize(:nfkc)", 2023, 4
    end

    # The value's bytes, read as UTF-8, as the pure-Ruby implementation
    # reads them. libidn reads them that way too, but idn-ruby crashes when
    # it rejects bytes from a string that isn't tagged as UTF-8, so those
    # raise ArgumentError when the value is split, before it's called. A
    # string in an encoding that isn't ASCII-compatible, such as UTF-16,
    # is left as it is, and still raises when it's split.
    def self.utf8(value)
      value = value.to_s
      return value unless value.encoding.ascii_compatible?
      value.dup.force_encoding(Encoding::UTF_8)
    end
    private_class_method :utf8

    # The errors .to_ascii raises for a domain name it can't convert.
    CONVERSION_ERRORS = [IDN::IDNError].freeze

    def self.to_ascii(value)
      utf8(value).split('.', -1).map do |segment|
        if segment.include?("\0")
          # libidn would read the NUL as the end of the label.
          segment
        elsif segment.size > 0 && segment.size < 64
          IDN::Idna.toASCII(segment, IDN::Idna::ALLOW_UNASSIGNED)
        elsif segment.size >= 64
          segment
        else
          ''
        end
      end.join('.')
    end

    # Characters that change how a label displays without being visible
    # themselves: controls, format characters such as bidi overrides and
    # isolates, and default ignorable code points. libidn rejects most of
    # them, but not those added to Unicode after the version it checks
    # against, such as U+2066 to U+2069. Format characters that are also
    # default ignorable are left out of the second set, since Ruby warns about
    # a duplicated range in a character class.
    DISPLAY_CHANGING = /[\p{Cc}\p{Cf}[\p{Default_Ignorable_Code_Point}&&\P{Cf}]]/

    # The label separators of IDNA2003 (Section 3.1 of RFC 3490, since
    # obsoleted by RFC 5890 and RFC 5891). A label that decodes to one of
    # them would display as two labels.
    LABEL_SEPARATORS = /[.\u3002\uFF0E\uFF61]/

    # A host name has only ASCII letters, digits and hyphens, and doesn't
    # start or end with a hyphen. RFC 3987 says to check an IRI's host names
    # with these rules (STD3, section 4.1 of RFC 3490), so a label that
    # decodes to anything else isn't displayed.
    NOT_STD3 = /[\x00-\x2C\x2E\x2F\x3A-\x40\x5B-\x60\x7B-\x7F]|\A-|-\z/

    def self.to_unicode(value)
      utf8(value).split('.', -1).map do |segment|
        if segment.include?("\0")
          # libidn would read the NUL as the end of the label.
          segment
        elsif segment.size > 0 && segment.size < 64
          decoded = IDN::Idna.toUnicode(segment, IDN::Idna::ALLOW_UNASSIGNED)
          if decoded =~ DISPLAY_CHANGING || decoded =~ LABEL_SEPARATORS ||
              decoded =~ NOT_STD3
            segment
          else
            decoded
          end
        elsif segment.size >= 64
          segment
        else
          ''
        end
      end.join('.')
    end
  end
end
