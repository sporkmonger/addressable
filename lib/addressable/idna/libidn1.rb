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

      def self.to_ascii(value)
        IDN::Idna.toASCII(value, IDN::Idna::ALLOW_UNASSIGNED)
      end

      def self.to_unicode(value)
        IDN::Idna.toUnicode(value, IDN::Idna::ALLOW_UNASSIGNED)
      end
    end
  end
end
