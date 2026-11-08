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

module Addressable
  module IDNA
    # All IDNA conversion related errors
    class Error < StandardError; end
    # Input is invalid.
    class PunycodeBadInput < Error; end
    # Output would exceed the space provided.
    class PunycodeBigOutput < Error; end
    # Input needs wider integers to process.
    class PunycodeOverflow < Error; end

    # Characters that change how a label displays without being visible
    # themselves: controls, format characters such as bidi overrides and
    # isolates, and default ignorable code points, including those added to
    # Unicode after the version a backend checks against. A label that
    # decodes to one of them is left as an A-label. Format characters that
    # are also default ignorable are left out of the second set, since Ruby
    # warns about a duplicated range in a character class.
    DISPLAY_CHANGING = /[\p{Cc}\p{Cf}[\p{Default_Ignorable_Code_Point}&&\P{Cf}]]/

    class << self
      attr_accessor :backend, :strict_mode

      # public interface implemented by all backends
      def to_ascii(value)
        value = value.to_s unless value.is_a?(String)
        backend.to_ascii(value)
      rescue Error
        strict_mode ? raise : value
      end

      def to_unicode(value)
        value = value.to_s unless value.is_a?(String)
        backend.to_unicode(value)
      rescue Error
        strict_mode ? raise : value
      end

      # @deprecated Use {String#unicode_normalize(:nfkc)} instead
      def unicode_normalize_kc(value)
        value.to_s.unicode_normalize(:nfkc)
      end

      extend Gem::Deprecate
      deprecate :unicode_normalize_kc, "String#unicode_normalize(:nfkc)", 2023, 4
    end
  end
end
