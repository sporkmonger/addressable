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

# libidn1 implementing IDNA2003
require "idn"

module Addressable
  module IDNA
    module Libidn1
      class << self
        # @deprecated Use {String#unicode_normalize(:nfkc)} instead
        def unicode_normalize_kc(value)
          value.to_s.unicode_normalize(:nfkc)
        end

        extend Gem::Deprecate
        deprecate :unicode_normalize_kc, "String#unicode_normalize(:nfkc)", 2023, 4
      end

      # Labels are converted separately, since libidn fails on a name with an
      # empty label, and a label that can't be converted is kept unchanged.
      def self.to_ascii(value)
        value.split('.', -1).map do |label|
          begin
            label.empty? ? label : IDN::Idna.toASCII(label, IDN::Idna::ALLOW_UNASSIGNED)
          rescue IDN::Idna::IdnaError => e
            Addressable::IDNA.strict_mode ? raise(Error.new(e.message)) : label
          end
        end.join('.')
      end

      # Characters that change how a label displays without being visible
      # themselves: controls, format characters such as bidi overrides and
      # isolates, and default ignorable code points. libidn rejects most of
      # them, but not those added to Unicode after the version it checks
      # against, such as U+2066 to U+2069. Format characters that are also
      # default ignorable are left out of the second set, since Ruby warns
      # about a duplicated range in a character class.
      DISPLAY_CHANGING = /[\p{Cc}\p{Cf}[\p{Default_Ignorable_Code_Point}&&\P{Cf}]]/

      def self.to_unicode(value)
        value.split('.', -1).map do |label|
          next label if label.empty?
          begin
            decoded = IDN::Idna.toUnicode(label, IDN::Idna::ALLOW_UNASSIGNED)
            decoded =~ DISPLAY_CHANGING ? label : decoded
          rescue IDN::Idna::IdnaError => e
            Addressable::IDNA.strict_mode ? raise(Error.new(e.message)) : label
          end
        end.join('.')
      end
    end
  end
end
