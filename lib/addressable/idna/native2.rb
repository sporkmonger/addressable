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

# libidn2 implementing IDNA2008+TR46
require "ffi"

module Addressable
  module IDNA
    extend FFI::Library

    ffi_lib ["idn2", "libidn2.0", "libidn2.so.0"]

    attach_function :idn2_to_ascii_8z, %i[string pointer int], :int
    attach_function :idn2_to_unicode_8z8z, %i[string pointer int], :int
    attach_function :idn2_strerror, [:int], :string
    attach_function :idn2_free, [:pointer], :void

    IDN2_TRANSITIONAL = 4
    IDN2_NONTRANSITIONAL = 8

    class << self
      # @deprecated Use {String#unicode_normalize(:nfkc)} instead
      def unicode_normalize_kc(value)
        value.to_s.unicode_normalize(:nfkc)
      end

      extend Gem::Deprecate
      deprecate :unicode_normalize_kc, "String#unicode_normalize(:nfkc)", 2023, 4
    end

    def self.to_ascii(value)
      return value if value.ascii_only?
      pointer = FFI::MemoryPointer.new(:pointer)
      res = idn2_to_ascii_8z(value, pointer, IDN2_NONTRANSITIONAL)
      # Fallback to Transitional mode in case of disallowed character
      res = idn2_to_ascii_8z(value, pointer, IDN2_TRANSITIONAL) if res != 0
      raise "libidn2 failed to convert \"#{value}\" to ascii (#{idn2_strerror(res)})" if res != 0
      result = pointer.read_pointer.read_string
      idn2_free(pointer.read_pointer)
      result
    end

    def self.to_unicode(value)
      pointer = FFI::MemoryPointer.new(:pointer)
      res = idn2_to_unicode_8z8z(value, pointer, IDN2_NONTRANSITIONAL)
      return value if res != 0
      result = pointer.read_pointer.read_string
      idn2_free(pointer.read_pointer)
      result.force_encoding('UTF-8')
    end
  end
end
