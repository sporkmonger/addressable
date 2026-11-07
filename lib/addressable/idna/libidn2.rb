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
    module Libidn2
      extend FFI::Library

      ffi_lib ["idn2", "libidn2.0", "libidn2.so.0"]

      attach_function :idn2_to_ascii_8z, %i[string pointer int], :int
      attach_function :idn2_to_unicode_8z8z, %i[string pointer int], :int
      attach_function :idn2_strerror, [:int], :string
      attach_function :idn2_free, [:pointer], :void

      IDN2_TRANSITIONAL = 4
      IDN2_NONTRANSITIONAL = 8

      def self.to_ascii(value)
        pointer = FFI::MemoryPointer.new(:pointer)
        res = idn2_to_ascii_8z(value, pointer, IDN2_NONTRANSITIONAL)
        # Fallback to Transitional mode in case of disallowed character
        res = idn2_to_ascii_8z(value, pointer, IDN2_TRANSITIONAL) if res == -304
        raise Error.new("libidn2 failed to convert \"#{value}\" to ascii (#{idn2_strerror(res)})") if res != 0
        result = pointer.read_pointer.read_string
        idn2_free(pointer.read_pointer)
        result
      end

      # Characters that change how a label displays without being visible
      # themselves: controls, format characters such as bidi overrides and
      # isolates, and default ignorable code points. Format characters that
      # are also default ignorable are left out of the second set, since Ruby
      # warns about a duplicated range in a character class.
      DISPLAY_CHANGING = /[\p{Cc}\p{Cf}[\p{Default_Ignorable_Code_Point}&&\P{Cf}]]/

      # libidn2 decodes Punycode without validating the result, so each label
      # is checked separately: a label is only decoded if it converts back to
      # itself with to_ascii and has no character that changes how it
      # displays. Otherwise it's returned unchanged.
      def self.to_unicode(value)
        value.split('.', -1).map do |label|
          next label if label.empty?
          begin
            decoded = label_to_unicode(label)
          rescue Error
            raise if Addressable::IDNA.strict_mode
            next label
          end
          next decoded if decoded == label
          next label if decoded =~ DISPLAY_CHANGING
          valid = begin
            to_ascii(decoded).casecmp(label) == 0
          rescue Error
            false
          end
          valid ? decoded : label
        end.join('.')
      end

      def self.label_to_unicode(label)
        pointer = FFI::MemoryPointer.new(:pointer)
        res = idn2_to_unicode_8z8z(label, pointer, IDN2_NONTRANSITIONAL)
        raise Error.new("libidn2 failed to convert \"#{label}\" to unicode (#{idn2_strerror(res)})") if res != 0
        result = pointer.read_pointer.read_string
        idn2_free(pointer.read_pointer)
        result.force_encoding('UTF-8')
      end
      private_class_method :label_to_unicode
    end
  end
end
