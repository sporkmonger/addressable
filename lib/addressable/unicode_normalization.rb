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
  ##
  # Unicode normalization in time linear in the length of the input.
  #
  # <code>String#unicode_normalize</code> normalizes a character and the
  # combining marks after it as one unit, in time quadratic in the number of
  # marks, so a few thousand marks in a row take seconds.
  #
  # @api private
  module UnicodeNormalization
    ##
    # The longest run of combining marks that is normalized. This is the
    # limit of the Stream-Safe Text Format in UAX #15; text in any language
    # stays well below it.
    MAX_COMBINING_MARKS = 30

    # U+FF9E and U+FF9F aren't combining marks, but NFKC and NFKD map them
    # to U+3099 and U+309A, which are.
    LONG_COMBINING_RUN =
      /([\p{M}ﾞﾟ]{#{MAX_COMBINING_MARKS + 1},})/
    private_constant :LONG_COMBINING_RUN

    ##
    # Normalizes a string, leaving runs of more than
    # <code>MAX_COMBINING_MARKS</code> combining marks as they are.
    #
    # @param [String] string The string to normalize.
    # @param [Symbol] form The normalization form.
    #
    # @return [String] The normalized string.
    def self.normalize(string, form)
      return string.unicode_normalize(form) if LONG_COMBINING_RUN !~ string

      string.split(LONG_COMBINING_RUN).each_slice(2).map do |text, marks|
        "#{text.unicode_normalize(form)}#{marks}"
      end.join
    end
  end
end
