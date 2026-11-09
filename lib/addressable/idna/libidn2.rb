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

require "addressable/idna/core"

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

      # Labels are converted separately, like the other backends do, so a
      # label that can't be converted is kept unchanged without preventing
      # the conversion of the others (unless strict_mode is on).
      def self.to_ascii(value)
        value.split('.', -1).map do |label|
          next label if label.empty?
          begin
            label_to_ascii(label)
          rescue Error
            raise if Addressable::IDNA.strict_mode
            label
          end
        end.join('.')
      end

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
            label_to_ascii(decoded).casecmp(label) == 0
          rescue Error
            false
          end
          valid ? decoded : label
        end.join('.')
      end

      def self.label_to_ascii(label)
        pointer = FFI::MemoryPointer.new(:pointer)
        res = idn2_to_ascii_8z(label, pointer, IDN2_NONTRANSITIONAL)
        # Fallback to Transitional mode in case of disallowed character
        res = idn2_to_ascii_8z(label, pointer, IDN2_TRANSITIONAL) if res == -304
        raise Error.new("libidn2 failed to convert \"#{label}\" to ascii (#{idn2_strerror(res)})") if res != 0
        result = pointer.read_pointer.read_string
        idn2_free(pointer.read_pointer)
        result
      end
      private_class_method :label_to_ascii

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
